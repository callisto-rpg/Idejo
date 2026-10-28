# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Reactions do
  @moduledoc """
  Reactions to messages (TP-17; steward decision, 2026-10-22).

  Any signed-in, verified reader who may view a topic reacts to its messages with emoji
  (`Idejo.Emoji`): `toggle/3` adds one, or takes it back when they had it. A user may add
  several emoji to one message. Messages deleted by a moderator (MO-02) and topics that are
  locked or archived (read only) take no reactions.

  Reactions store no notification: they show under the message (steward decision,
  2026-10-23, with the Notifications page gone), and the author gets a live bubble
  (`Idejo.Notifications.announce_reaction/3`). After each change the topic's viewers get
  `{:reactions, message_id, summary}`, worked out once (NF-01).
  """
  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Emoji
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.{Message, Reaction}
  alias Idejo.Notifications
  alias Idejo.RateLimit
  alias Idejo.Repo

  @typedoc "One emoji's reactions to a message, in the order they were first used."
  @type summary :: [%{emoji: String.t(), count: pos_integer(), user_ids: [Ecto.UUID.t()]}]

  @doc """
  Adds the user's reaction `emoji` (a name) to the message, or takes it back when they had it.
  Returns the message's new summary.
  """
  @spec toggle(User.t(), Message.t(), String.t()) ::
          {:ok, summary()} | {:error, :forbidden | :unknown_emoji | :rate_limited}
  def toggle(%User{} = user, %Message{} = message, emoji) when is_binary(emoji) do
    cond do
      not may_react?(user, message) -> {:error, :forbidden}
      Emoji.lookup(emoji) == nil -> {:error, :unknown_emoji}
      RateLimit.check(:react, user.id) != :ok -> {:error, :rate_limited}
      true -> save(user, message, Emoji.lookup(emoji).name)
    end
  end

  defp save(user, message, emoji) do
    {:ok, {summary, added?}} =
      Repo.transact(fn ->
        existing = Repo.get_by(Reaction, message_id: message.id, user_id: user.id, emoji: emoji)

        if existing do
          Repo.delete!(existing)
        else
          Repo.insert!(%Reaction{message_id: message.id, user_id: user.id, emoji: emoji},
            on_conflict: :nothing
          )
        end

        {:ok, {summary(message.id), is_nil(existing)}}
      end)

    Messages.broadcast(message.topic_id, {:reactions, message.id, summary})
    # A bubble for the author, live only (steward decision, 2026-10-23).
    if added?, do: Notifications.announce_reaction(user, message, Emoji.lookup(emoji))
    {:ok, summary}
  end

  @doc """
  Returns true when the user may react to the message: signed in and verified, the message
  not deleted, and its topic one they may view (or a private conversation they are in)
  that is neither locked nor archived.
  """
  @spec may_react?(User.t() | nil, Message.t()) :: boolean()
  def may_react?(nil, _message), do: false

  def may_react?(%User{} = user, %Message{} = message) do
    Accounts.confirmed?(user) and is_nil(message.deleted_at) and
      case Forum.get_readable_topic(user, message.topic_id) do
        %{state: "open"} -> true
        _ -> false
      end
  end

  @doc "The summaries of the given messages' reactions, as `%{message_id => summary}`."
  @spec summaries([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => summary()}
  def summaries([]), do: %{}

  def summaries(message_ids) do
    from(r in Reaction,
      where: r.message_id in ^message_ids,
      order_by: [asc: r.created_at, asc: r.id],
      select: {r.message_id, r.emoji, r.user_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_, emoji, user_id} -> {emoji, user_id} end)
    |> Map.new(fn {message_id, rows} -> {message_id, summarise(rows)} end)
  end

  @doc """
  Who reacted to the message, and with what (steward decision, 2026-10-28): each user once,
  in the order of their first reaction, with their emoji names in the order they chose them.
  Asked only when a reader opens the list, so the summaries stay free of names (NF-01).
  """
  @spec reactors(Ecto.UUID.t()) :: [%{user: User.t(), emoji: [String.t()]}]
  def reactors(message_id) do
    from(r in Reaction,
      join: u in assoc(r, :user),
      where: r.message_id == ^message_id,
      order_by: [asc: r.created_at, asc: r.id],
      select: {u, r.emoji}
    )
    |> Repo.all()
    |> Enum.reduce({[], %{}}, fn {user, emoji}, {order, emoji_by} ->
      order = if Map.has_key?(emoji_by, user.id), do: order, else: [user | order]
      {order, Map.update(emoji_by, user.id, [emoji], &(&1 ++ [emoji]))}
    end)
    |> then(fn {order, emoji_by} ->
      for user <- Enum.reverse(order), do: %{user: user, emoji: emoji_by[user.id]}
    end)
  end

  @doc "The summary of one message's reactions."
  @spec summary(Ecto.UUID.t()) :: summary()
  def summary(message_id), do: Map.get(summaries([message_id]), message_id, [])

  # Each emoji once, where it was first used, with everyone who used it.
  defp summarise(rows) do
    rows
    |> Enum.reduce({[], %{}}, fn {emoji, user_id}, {order, users} ->
      order = if Map.has_key?(users, emoji), do: order, else: [emoji | order]
      {order, Map.update(users, emoji, [user_id], &(&1 ++ [user_id]))}
    end)
    |> then(fn {order, users} ->
      for emoji <- Enum.reverse(order),
          do: %{emoji: emoji, count: length(users[emoji]), user_ids: users[emoji]}
    end)
  end
end
