# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Conversations do
  @moduledoc """
  Private conversations (steward decision, 2026-10-27, departing from v1, which has no
  direct messages): a topic between two members, outside every category (`topics.private`,
  `category_id` nil), read only by its participants (`conversation_participants`).

  With no category, `Idejo.Access.can?/3` gives nobody a right there, owners and
  administrators included, and every query that goes through categories (lists, search, the
  sitemap, unread, the sidebar) leaves them out. The ways in are here: `get/2` for a
  participant, `can_post?/2`. A participant may report a message (MO-01): server moderators
  then see that message in the queue, never the rest of the conversation.

  Messages grow as anywhere else, but without slow mode: they open with no window, so
  Ctrl+Enter starts a new one at once (`Idejo.Messages.may_start_new?/2`). The first one is
  written in the composer too: there is no opening post.
  """
  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Conversations.Participant
  alias Idejo.Federation
  alias Idejo.Forum.Topic
  alias Idejo.Messages.Message
  alias Idejo.RateLimit
  alias Idejo.Reading
  alias Idejo.Repo

  @title "Private conversation"

  @doc """
  Whether `sender` may start a private conversation with `recipient`, or write in theirs:
  a verified member (AC-01) who is not banned, writing to someone else whose account is
  active, not banned, and accepts private messages.
  """
  @spec may_message?(User.t() | nil, User.t()) :: boolean()
  def may_message?(nil, _recipient), do: false
  def may_message?(%User{id: id}, %User{id: id}), do: false

  def may_message?(%User{} = sender, %User{} = recipient) do
    sender.status == "active" and Accounts.confirmed?(sender) and not Accounts.banned?(sender) and
      receives?(recipient)
  end

  defp receives?(user),
    do: user.status == "active" and user.accepts_private_messages and not Accounts.banned?(user)

  @doc """
  The private conversation between `sender` and `recipient`, started when there is none
  yet: `{:ok, topic}`. Both follow it, so each hears of the other's messages (NO-01).
  `{:error, :forbidden}` unless `may_message?/2`; a new one counts as a new topic (SP-05).
  """
  @spec start(User.t(), User.t()) :: {:ok, Topic.t()} | {:error, :forbidden | :rate_limited}
  def start(%User{} = sender, %User{} = recipient) do
    if may_message?(sender, recipient),
      do: Repo.transact(fn -> find_or_create(sender, recipient) end),
      else: {:error, :forbidden}
  end

  defp find_or_create(sender, recipient) do
    # One conversation per pair, even when both start one at the same moment.
    pair = Enum.join(Enum.sort([sender.id, recipient.id]), ":")
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["conversation:" <> pair])

    case between(sender, recipient) do
      %Topic{} = topic -> {:ok, topic}
      nil -> create(sender, recipient)
    end
  end

  defp between(a, b) do
    Repo.one(
      from t in Topic,
        join: pa in Participant,
        on: pa.topic_id == t.id and pa.user_id == ^a.id,
        join: pb in Participant,
        on: pb.topic_id == t.id and pb.user_id == ^b.id,
        where: t.private,
        limit: 1
    )
  end

  defp create(sender, recipient) do
    with :ok <- RateLimit.check(:new_topic, sender.id) do
      now = DateTime.utc_now()
      id = Federation.generate_id()

      topic =
        Repo.insert!(%Topic{
          id: id,
          uri: Federation.uri(:topic, id),
          private: true,
          author_id: sender.id,
          title: @title,
          slug: "private-conversation",
          last_activity_at: now
        })

      for user <- [sender, recipient] do
        Repo.insert!(%Participant{topic_id: id, user_id: user.id})
        Reading.auto_follow(user.id, id)
      end

      {:ok, topic}
    end
  end

  @doc "The private conversation with that id, when `user` takes part in it; else nil."
  @spec get(User.t() | nil, String.t()) :: Topic.t() | nil
  def get(nil, _id), do: nil

  def get(%User{id: user_id}, id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.one(
          from t in Topic,
            join: p in Participant,
            on: p.topic_id == t.id and p.user_id == ^user_id,
            where: t.id == ^id and t.private,
            preload: [:category, :tags]
        )

      :error ->
        nil
    end
  end

  @doc "Whether the user takes part in the private conversation."
  @spec participant?(User.t() | nil, Topic.t()) :: boolean()
  def participant?(nil, _topic), do: false

  def participant?(%User{id: user_id}, %Topic{id: topic_id}),
    do:
      Repo.exists?(
        from p in Participant, where: p.topic_id == ^topic_id and p.user_id == ^user_id
      )

  @doc "The ids of the conversation's participants."
  @spec participant_ids(Topic.t()) :: [Ecto.UUID.t()]
  def participant_ids(%Topic{id: topic_id}),
    do: Repo.all(from p in Participant, where: p.topic_id == ^topic_id, select: p.user_id)

  @doc """
  The other participants of the conversation, for `user`: whom the page and its card name.
  """
  @spec others(Topic.t(), User.t()) :: [User.t()]
  def others(%Topic{id: topic_id}, %User{id: user_id}) do
    Repo.all(
      from u in User,
        join: p in Participant,
        on: p.user_id == u.id,
        where: p.topic_id == ^topic_id and u.id != ^user_id,
        order_by: u.username
    )
  end

  @doc """
  Whether `user` may write in the private conversation: a participant who may still message
  every other participant (`may_message?/2`: an account deleted, banned or no longer
  accepting private messages ends it for both).
  """
  @spec can_post?(User.t() | nil, Topic.t()) :: boolean()
  def can_post?(nil, _topic), do: false
  def can_post?(_user, %Topic{state: state}) when state != "open", do: false

  def can_post?(%User{} = user, %Topic{private: true} = topic) do
    others = others(topic, user)
    participant?(user, topic) and others != [] and Enum.all?(others, &may_message?(user, &1))
  end

  def can_post?(_user, _topic), do: false

  @doc """
  The user's private conversations, the most recently active first, as cards:
  `[%{topic: topic, others: [user], last: message | nil, unread: count}]`, `last` the newest
  message not deleted.
  """
  @spec list(User.t()) :: [map()]
  def list(%User{id: user_id} = user) do
    topics =
      Repo.all(
        from t in Topic,
          join: p in Participant,
          on: p.topic_id == t.id and p.user_id == ^user_id,
          where: t.private,
          order_by: [desc: t.last_activity_at, desc: t.id],
          preload: [participants: :user]
      )

    ids = Enum.map(topics, & &1.id)
    unread = Reading.unread_counts(user, ids)
    last = last_messages(ids)

    for topic <- topics do
      %{
        topic: topic,
        others: for(%{user: u} <- topic.participants, u.id != user_id, do: u),
        last: last[topic.id],
        unread: Map.get(unread, topic.id, 0)
      }
    end
  end

  defp last_messages([]), do: %{}

  defp last_messages(topic_ids) do
    Repo.all(
      from m in Message,
        where: m.topic_id in ^topic_ids and is_nil(m.deleted_at),
        distinct: m.topic_id,
        order_by: [asc: m.topic_id, desc: m.opened_at, desc: m.id],
        preload: :author
    )
    |> Map.new(&{&1.topic_id, &1})
  end

  @doc """
  The user's unread private messages, for a push: how many in all (a growing message once),
  and the names of the people who wrote them, those of the latest conversations first, at
  most three.
  """
  @spec unread_summary(User.t()) :: %{count: non_neg_integer(), names: [String.t()]}
  def unread_summary(%User{} = user) do
    counts = Reading.unread_counts(user, conversation_ids(user))

    names =
      Repo.all(
        from t in Topic,
          join: p in Participant,
          on: p.topic_id == t.id and p.user_id != ^user.id,
          join: u in User,
          on: u.id == p.user_id,
          where: t.id in ^Map.keys(counts),
          order_by: [desc: t.last_activity_at, asc: u.username],
          select: u.display_name
      )
      |> Enum.uniq()
      |> Enum.take(3)

    %{count: counts |> Map.values() |> Enum.sum(), names: names}
  end

  @doc "How many of the user's private conversations have unread messages: the sidebar's dot."
  @spec unread_count(User.t() | nil) :: non_neg_integer()
  def unread_count(nil), do: 0

  def unread_count(%User{} = user),
    do: user |> Reading.unread_counts(conversation_ids(user)) |> map_size()

  defp conversation_ids(%User{id: user_id}) do
    Repo.all(
      from p in Participant,
        join: t in Topic,
        on: t.id == p.topic_id,
        where: p.user_id == ^user_id and t.private,
        select: p.topic_id
    )
  end
end
