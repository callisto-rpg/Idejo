# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Reading do
  @moduledoc """
  Unread tracking (TP-07): each user's read position per topic, the unread marker of topic
  lists (TP-03) and the topics with something new across categories. And following topics
  (TP-13).

  Opening a topic marks everything in it read, and so does each message that arrives while
  the topic is open (steward decision). A message is unread when it was opened after the read
  position's message and by someone else. A growing message keeps its `opened_at`, so it is
  one unread item and does not turn unread again as it grows (GM-13).

  With no position, a topic counts as read up to the user's sign-up: a new member does not
  start with every old topic marked new.

  Following (steward decision): starting a topic or posting in it follows it
  (`auto_follow/2`, in the same transaction), and followers are notified of new messages
  (NO-01, with notifications). An explicit unfollow is kept as `following: false`, so posting
  again does not follow again; only "Follow" does.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Tags, Topic}
  alias Idejo.Messages.Message
  alias Idejo.Reading.{Follow, ReadPosition}
  alias Idejo.Repo

  @doc """
  Marks everything in the topic read for the user: their position moves to its latest
  message. Visitors (`nil`) have no position.
  """
  @spec mark_read(User.t() | nil, Topic.t()) :: :ok
  def mark_read(nil, _topic), do: :ok

  def mark_read(%User{id: user_id}, %Topic{id: topic_id}) do
    latest =
      from(m in Message,
        where: m.topic_id == ^topic_id,
        order_by: [desc: m.opened_at, desc: m.id],
        limit: 1,
        select: m.id
      )
      |> Repo.one()

    Repo.insert!(
      %ReadPosition{user_id: user_id, topic_id: topic_id, last_read_message_id: latest},
      on_conflict: {:replace, [:last_read_message_id, :updated_at]},
      conflict_target: [:user_id, :topic_id]
    )

    :ok
  end

  @doc "Follows the topic (TP-13), also after an earlier unfollow."
  @spec follow(User.t(), Topic.t()) :: :ok
  def follow(%User{} = user, %Topic{} = topic), do: set_following(user.id, topic.id, true)

  @doc "Stops following the topic (TP-13); posting there later does not follow it again."
  @spec unfollow(User.t(), Topic.t()) :: :ok
  def unfollow(%User{} = user, %Topic{} = topic), do: set_following(user.id, topic.id, false)

  @doc """
  Follows the topic for its starter or a poster, unless they unfollowed it before. Called
  inside the transaction that writes their message.
  """
  @spec auto_follow(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, :followed}
  def auto_follow(user_id, topic_id) do
    Repo.insert!(%Follow{user_id: user_id, topic_id: topic_id, following: true},
      on_conflict: :nothing,
      conflict_target: [:user_id, :topic_id]
    )

    {:ok, :followed}
  end

  @doc "Returns true when the user follows the topic. Visitors follow nothing."
  @spec following?(User.t() | nil, Topic.t()) :: boolean()
  def following?(nil, _topic), do: false

  def following?(%User{id: user_id}, %Topic{id: topic_id}) do
    Repo.exists?(
      from f in Follow,
        where: f.user_id == ^user_id and f.topic_id == ^topic_id and f.following
    )
  end

  @doc """
  The topics the user follows in categories they may view, in the order they started
  following them (oldest first, so the sidebar list stays put). Visitors follow nothing.
  """
  @spec list_followed_topics(User.t() | nil) :: [Topic.t()]
  def list_followed_topics(nil), do: []

  def list_followed_topics(%User{id: user_id} = user) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    Repo.all(
      from t in Topic,
        join: f in Follow,
        on: f.topic_id == t.id and f.user_id == ^user_id and f.following,
        where: t.category_id in subquery(viewable),
        order_by: [asc: f.created_at, asc: t.id]
    )
  end

  defp set_following(user_id, topic_id, following) do
    Repo.insert!(%Follow{user_id: user_id, topic_id: topic_id, following: following},
      on_conflict: {:replace, [:following, :updated_at]},
      conflict_target: [:user_id, :topic_id]
    )

    :ok
  end

  @doc """
  Returns the number of unread messages in each of the given topics that has any, as
  `%{topic_id => count}`. Visitors get `%{}`.
  """
  @spec unread_counts(User.t() | nil, [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => pos_integer()}
  def unread_counts(nil, _topic_ids), do: %{}
  def unread_counts(_user, []), do: %{}

  def unread_counts(%User{} = user, topic_ids) do
    user
    |> unread_messages()
    |> where([m], m.topic_id in ^topic_ids)
    |> group_by([m], m.topic_id)
    |> select([m], {m.topic_id, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  What is new for the user in each of the given topics, for the dots of the sidebar (steward
  decision, 2026-10-23), as `%{topic_id => :new | :role_mention | :reply | :mention}`; topics
  with nothing unread are left out. Among the unread messages (`unread_counts/2`'s):
  `:mention` when one @mentions the user, else `:reply` when one replies to them, else
  `:role_mention` when one +mentions one of their roles, else `:new`. Read from their
  notifications (NO-01), so the strongest wins.
  """
  @spec activity(User.t() | nil, [Ecto.UUID.t()]) ::
          %{Ecto.UUID.t() => :new | :role_mention | :reply | :mention}
  def activity(nil, _topic_ids), do: %{}
  def activity(_user, []), do: %{}

  def activity(%User{id: user_id} = user, topic_ids) do
    user
    |> unread_messages()
    |> where([m], m.topic_id in ^topic_ids)
    |> join(:left, [m], n in Idejo.Notifications.Notification,
      on: n.message_id == m.id and n.user_id == ^user_id
    )
    |> group_by([m], m.topic_id)
    |> select([m, ..., n], {
      m.topic_id,
      max(
        fragment(
          "CASE ? WHEN 'mention' THEN 4 WHEN 'reply' THEN 3 WHEN 'role_mention' THEN 2 ELSE 1 END",
          n.kind
        )
      )
    })
    |> Repo.all()
    |> Map.new(fn {topic_id, level} ->
      {topic_id, Enum.at([:new, :role_mention, :reply, :mention], level - 1)}
    end)
  end

  @doc """
  The topics with unread messages across every category the user may view, most recently
  active first, 30 a page: `{[{topic, unread_count}], more?}`. Topics come with their author
  and category. `following: false` leaves out the topics the user follows (the Unread page
  lists those apart, `list_unread_followed_topics/1`).
  """
  @spec list_unread_topics(User.t(), keyword()) :: {[{Topic.t(), pos_integer()}], boolean()}
  def list_unread_topics(%User{} = user, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 30)
    page = max(Keyword.get(opts, :page, 1), 1)

    query =
      if Keyword.get(opts, :following, true),
        do: unread_topics(user),
        else: from(t in unread_topics(user), where: t.id not in subquery(followed_ids(user)))

    rows =
      Repo.all(
        from t in query,
          offset: ^((page - 1) * per_page),
          limit: ^(per_page + 1)
      )

    {Enum.take(rows, per_page), length(rows) > per_page}
  end

  @doc """
  Every topic the user follows (TP-13) that has unread messages, most recently active
  first, all of them: `[{topic, unread_count}]`, for the top of the Unread page (steward
  decision, 2026-10-23).
  """
  @spec list_unread_followed_topics(User.t()) :: [{Topic.t(), pos_integer()}]
  def list_unread_followed_topics(%User{} = user) do
    Repo.all(from t in unread_topics(user), where: t.id in subquery(followed_ids(user)))
  end

  # The topics with unread messages in viewable categories, with their counts, newest first.
  defp unread_topics(user) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    counts =
      user
      |> unread_messages()
      |> group_by([m], m.topic_id)
      |> select([m], %{topic_id: m.topic_id, count: count(m.id)})

    from t in Topic,
      join: c in subquery(counts),
      on: c.topic_id == t.id,
      where: t.category_id in subquery(viewable),
      order_by: [desc: t.last_activity_at, desc: t.id],
      preload: [:author, :category, tags: ^Tags.ordered()],
      select: {t, c.count}
  end

  defp followed_ids(%User{id: user_id}),
    do: from(f in Follow, where: f.user_id == ^user_id and f.following, select: f.topic_id)

  # Messages by others opened after the user's read position in their topic, or after the
  # user signed up where they have none.
  defp unread_messages(%User{id: user_id, created_at: signed_up}) do
    from m in Message,
      left_join: rp in ReadPosition,
      on: rp.topic_id == m.topic_id and rp.user_id == ^user_id,
      left_join: last in Message,
      on: last.id == rp.last_read_message_id,
      where: m.author_id != ^user_id,
      # MO-02: a message deleted by a moderator is nothing new to read.
      where: is_nil(m.deleted_at),
      where:
        m.opened_at >
          coalesce(
            last.opened_at,
            coalesce(rp.updated_at, type(^signed_up, :utc_datetime_usec))
          )
  end
end
