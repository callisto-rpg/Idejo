# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Scheduling do
  @moduledoc """
  Scheduled messages (`!schedule` in the composer; steward decision, 2026-10-23): text not
  sent yet, posted in its topic after a delay of up to #{168} hours, hours with decimals.

  Until then only its author sees it (`list_pending/2`) and may cancel it (`cancel/2`). It
  never grows: at its time `Idejo.Messages.ScheduledWorker` posts it closed, with
  `Idejo.Forum.post_message/4`, as its author, marked `scheduled`, so readers see a
  "scheduled message" label. The author's rights are checked again then: a message that may
  no longer be posted (locked topic, rights gone, account banned or deleted) is dropped.

  Each change reaches the topic's viewers as `{:scheduled, author_id}`, for the author's
  views to reload their list.
  """
  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Federation
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages
  alias Idejo.Messages.{ScheduledMessage, ScheduledWorker}
  alias Idejo.RateLimit
  alias Idejo.Repo

  @max_hours 168

  @doc "The longest delay, in hours."
  @spec max_hours() :: pos_integer()
  def max_hours, do: @max_hours

  @doc """
  Reads a delay in hours, with decimals (`"1.5"`, `"0,25"`), into seconds: more than 0 and
  at most #{@max_hours} hours, at least a minute.
  """
  @spec parse_hours(String.t()) :: {:ok, pos_integer()} | :error
  def parse_hours(text) when is_binary(text) do
    case text |> String.trim() |> String.replace(",", ".") |> Float.parse() do
      {hours, ""} when hours > 0 and hours <= @max_hours -> {:ok, max(round(hours * 3600), 60)}
      _ -> :error
    end
  end

  def parse_hours(_text), do: :error

  @doc """
  Schedules `body` in the topic, as `user`, `seconds` from now, replying to
  `opts[:reply_to_id]` when given (a message of the same topic). Needs the post right now,
  as when it is posted.
  """
  @spec schedule(User.t(), Topic.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, ScheduledMessage.t()} | {:error, :forbidden | :blank | :rate_limited}
  def schedule(%User{} = user, %Topic{} = topic, body, seconds, opts \\ []) do
    reply_to = Forum.get_topic_message(topic, opts[:reply_to_id])

    cond do
      not Forum.can_post?(user, topic) ->
        {:error, :forbidden}

      String.trim(body) == "" ->
        {:error, :blank}

      RateLimit.check(:new_message, user.id) != :ok ->
        {:error, :rate_limited}

      true ->
        post_at = DateTime.add(DateTime.utc_now(), seconds, :second)

        result =
          Repo.transact(fn ->
            scheduled =
              Repo.insert!(%ScheduledMessage{
                id: Federation.generate_id(),
                topic_id: topic.id,
                author_id: user.id,
                reply_to_id: reply_to && reply_to.id,
                body_md: body,
                post_at: post_at
              })

            {:ok, _job} =
              %{id: scheduled.id}
              |> ScheduledWorker.new(scheduled_at: post_at)
              |> Oban.insert()

            {:ok, scheduled}
          end)

        with {:ok, _} <- result, do: changed(topic.id, user.id)
        result
    end
  end

  @doc "The user's messages waiting to be posted in the topic, soonest first."
  @spec list_pending(User.t() | nil, Topic.t()) :: [ScheduledMessage.t()]
  def list_pending(nil, _topic), do: []

  def list_pending(%User{id: user_id}, %Topic{id: topic_id}) do
    Repo.all(
      from s in ScheduledMessage,
        where: s.author_id == ^user_id and s.topic_id == ^topic_id,
        order_by: [asc: s.post_at, asc: s.id]
    )
  end

  @doc "Cancels one of the user's scheduled messages; anyone else's, or a posted one, is not found."
  @spec cancel(User.t(), Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def cancel(%User{id: user_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {1, [topic_id]} <-
           Repo.delete_all(
             from s in ScheduledMessage,
               where: s.id == ^id and s.author_id == ^user_id,
               select: s.topic_id
           ) do
      changed(topic_id, user_id)
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Posts a scheduled message whose time has come, closed and marked `scheduled`; called by
  `Idejo.Messages.ScheduledWorker`. A cancelled one is gone already (`:ok`). One that may no
  longer be posted is dropped; `{:snooze, seconds}` when the author is sending too fast.
  """
  @spec post(Ecto.UUID.t()) :: :ok | {:snooze, pos_integer()}
  def post(id) do
    case Repo.get(ScheduledMessage, id) |> Repo.preload([:author, :topic]) do
      nil -> :ok
      scheduled -> post_scheduled(scheduled)
    end
  end

  defp post_scheduled(%{author: author, topic: topic} = scheduled) do
    attrs = %{"body" => scheduled.body_md, "reply_to_id" => scheduled.reply_to_id}

    result =
      if author.status == "active" and not Accounts.banned?(author),
        do: Forum.post_message(author, topic, attrs, scheduled: true),
        else: {:error, :forbidden}

    case result do
      {:error, :rate_limited} ->
        {:snooze, 60}

      _posted_or_refused ->
        Repo.delete_all(from s in ScheduledMessage, where: s.id == ^scheduled.id)
        changed(topic.id, author.id)
    end
  end

  defp changed(topic_id, author_id) do
    Messages.broadcast(topic_id, {:scheduled, author_id})
    :ok
  end
end
