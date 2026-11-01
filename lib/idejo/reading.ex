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

  A topic an administrator marked "followed by everyone" (`topics.autofollow`, steward
  decision, 2026-10-23) is followed by every user without a `follows` row for it, members
  who join later included, and listed as followed for visitors; an unfollow still holds.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Tags, Topic}
  alias Idejo.Messages.Message
  alias Idejo.Reading.{Follow, ReadPosition}
  alias Idejo.Repo
  alias Idejo.Settings

  @doc """
  Marks everything in the topic read for the user: their position moves to its latest
  message. Visitors (`nil`) have no position.
  """
  @spec mark_read(User.t() | nil, Topic.t()) :: :ok
  def mark_read(nil, _topic), do: :ok

  # One statement, which looks the latest message up itself (nil in a conversation with none
  # yet): every view of a topic runs this at each new message (NF-01).
  def mark_read(%User{id: user_id}, %Topic{id: topic_id}) do
    latest =
      from(m in Message,
        where: m.topic_id == ^topic_id,
        order_by: [desc: m.opened_at, desc: m.id],
        limit: 1,
        select: m.id
      )

    position = %{
      user_id: user_id,
      topic_id: topic_id,
      last_read_message_id: latest,
      updated_at: DateTime.utc_now()
    }

    Repo.insert_all(ReadPosition, [position],
      on_conflict: {:replace, [:last_read_message_id, :updated_at]},
      conflict_target: [:user_id, :topic_id]
    )

    :ok
  end

  @doc """
  Where the user left off in a topic they opened before: the oldest unread message and how
  many there are, as `%{id: message_id, count: n}`, for the topic page to open there with an
  "N unread messages" line (steward decision, 2026-10-23). Nil for visitors, for a topic the
  user never opened (no read position) and when nothing is unread. Call it before
  `mark_read/2`.
  """
  @spec first_unread(User.t() | nil, Topic.t()) ::
          %{id: Ecto.UUID.t(), count: pos_integer()} | nil
  def first_unread(nil, _topic), do: nil

  def first_unread(%User{} = user, %Topic{id: topic_id}) do
    summary =
      &select(&1, [m], %{
        id: type(fragment("(array_agg(? ORDER BY ?, ?))[1]", m.id, m.opened_at, m.id), Ecto.UUID),
        count: count(m.id)
      })

    Topic
    |> with_unread(user, summary)
    |> where([t, position: rp], t.id == ^topic_id and not is_nil(rp.user_id))
    |> select([unread: u], %{id: u.id, count: u.count})
    |> Repo.one()
  end

  @doc "Follows the topic (TP-13), also after an earlier unfollow; it is no longer muted."
  @spec follow(User.t(), Topic.t()) :: :ok
  def follow(%User{} = user, %Topic{} = topic) do
    Repo.insert!(%Follow{user_id: user.id, topic_id: topic.id, following: true, muted: false},
      on_conflict: {:replace, [:following, :muted, :updated_at]},
      conflict_target: [:user_id, :topic_id]
    )

    :ok
  end

  @doc """
  Unfollows and mutes the topic ("Unfollow & mute", steward decision, 2026-10-23): it sends
  the user no notification of any kind, @ and + mentions and replies included
  (`Idejo.Notifications`), stays off the Unread page and the header's count, and is not
  followed again by posting or being mentioned, until the user follows it again
  (`follow/2`).
  """
  @spec mute(User.t(), Topic.t()) :: :ok
  def mute(%User{} = user, %Topic{} = topic) do
    Repo.insert!(%Follow{user_id: user.id, topic_id: topic.id, following: false, muted: true},
      on_conflict: {:replace, [:following, :muted, :updated_at]},
      conflict_target: [:user_id, :topic_id]
    )

    :ok
  end

  @doc "The ids of the topics the user muted, as a query (for `not in subquery(...)`)."
  @spec muted_topic_ids(Ecto.UUID.t()) :: Ecto.Query.t()
  def muted_topic_ids(user_id),
    do: from(f in Follow, where: f.user_id == ^user_id and f.muted, select: f.topic_id)

  @doc """
  Marks the topic unread again from its latest message by someone else ("Mark unread",
  steward decision, 2026-10-23): the read position goes back to the message before it, so
  that message and any later ones by others count as new. Nothing changes when nobody else
  wrote in it.
  """
  @spec mark_unread(User.t(), Topic.t()) :: :ok
  def mark_unread(%User{id: user_id}, %Topic{id: topic_id}) do
    last_other =
      Repo.one(
        from m in Message,
          where: m.topic_id == ^topic_id and m.author_id != ^user_id and is_nil(m.deleted_at),
          order_by: [desc: m.opened_at, desc: m.id],
          limit: 1
      )

    if last_other, do: read_up_to_before(user_id, topic_id, last_other)
    :ok
  end

  defp read_up_to_before(user_id, topic_id, message) do
    before =
      Repo.one(
        from m in Message,
          where:
            m.topic_id == ^topic_id and
              (m.opened_at < ^message.opened_at or
                 (m.opened_at == ^message.opened_at and m.id < ^message.id)),
          order_by: [desc: m.opened_at, desc: m.id],
          limit: 1,
          select: m.id
      )

    # With nothing before it (it opened the topic), the position holds no message and its
    # time, which unread counts fall back on, goes just before it.
    Repo.insert_all(
      ReadPosition,
      [
        %{
          user_id: user_id,
          topic_id: topic_id,
          last_read_message_id: before,
          updated_at: DateTime.add(message.opened_at, -1, :microsecond)
        }
      ],
      on_conflict: {:replace, [:last_read_message_id, :updated_at]},
      conflict_target: [:user_id, :topic_id]
    )
  end

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

  @doc """
  Returns true when the user follows the topic: their `follows` row says so, or they have
  none and the topic is followed by everyone. Visitors follow nothing they could unfollow.
  """
  @spec following?(User.t() | nil, Topic.t()) :: boolean()
  def following?(nil, _topic), do: false

  def following?(%User{id: user_id}, %Topic{id: topic_id} = topic) do
    case Repo.one(
           from f in Follow,
             where: f.user_id == ^user_id and f.topic_id == ^topic_id,
             select: f.following
         ) do
      nil -> topic.autofollow
      following -> following
    end
  end

  @doc """
  The topics the user follows in categories they may view, in the order they started
  following them (oldest first, so the sidebar list stays put); a topic followed by
  everyone counts from its creation. Visitors get the topics followed by everyone that they
  may view.
  """
  @spec list_followed_topics(User.t() | nil) :: [Topic.t()]
  def list_followed_topics(nil) do
    viewable = Category |> Access.where_allowed(nil, :view) |> select([c], c.id)

    Repo.all(
      from t in Topic,
        where: t.autofollow and t.category_id in subquery(viewable),
        order_by: [asc: t.created_at, asc: t.id]
    )
  end

  def list_followed_topics(%User{} = user) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    Repo.all(
      from [t, f] in followed(user),
        where: t.category_id in subquery(viewable),
        order_by: [asc: coalesce(f.created_at, t.created_at), asc: t.id]
    )
  end

  @doc """
  Marks the topics nobody follows as inactive (`topic.inactive`; steward decision,
  2026-11-01): no active user has a `follows` row with `following`, and the topic is not
  followed by everyone (`autofollow`). One query for the whole list, and none while the
  "Allow inactive topics" setting (`inactive_topics`) is off. Takes topics or
  `{topic, extra}` tuples, as the lists hold them.
  """
  @spec put_inactive([Topic.t() | {Topic.t(), term()}]) :: [Topic.t() | {Topic.t(), term()}]
  def put_inactive([]), do: []

  def put_inactive(rows) do
    if Settings.get(:inactive_topics) do
      ids = Enum.map(rows, &(&1 |> row_topic() |> Map.fetch!(:id)))
      inactive = MapSet.new(inactive_topic_ids(ids))
      Enum.map(rows, &mark_inactive(&1, inactive))
    else
      rows
    end
  end

  defp row_topic({%Topic{} = topic, _extra}), do: topic
  defp row_topic(%Topic{} = topic), do: topic

  defp mark_inactive({topic, extra}, inactive), do: {mark_inactive(topic, inactive), extra}

  defp mark_inactive(%Topic{} = topic, inactive),
    do: %{topic | inactive: MapSet.member?(inactive, topic.id)}

  defp inactive_topic_ids(ids) do
    followed =
      from f in Follow,
        join: u in User,
        on: u.id == f.user_id,
        where: f.topic_id == parent_as(:topic).id and f.following and u.status == "active",
        select: 1

    Repo.all(
      from t in Topic,
        as: :topic,
        where: t.id in ^ids and not t.autofollow and not exists(subquery(followed)),
        select: t.id
    )
  end

  # The topics the user follows, with their `follows` row (nil for one followed by everyone).
  defp followed(%User{id: user_id}) do
    from t in Topic,
      left_join: f in Follow,
      on: f.topic_id == t.id and f.user_id == ^user_id,
      where: f.following or (t.autofollow and is_nil(f.user_id))
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
    Topic
    |> with_unread(user, &count_unread/1)
    |> where([t], t.id in ^topic_ids)
    |> select([t, unread: u], {t.id, u.count})
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
    summary = fn unread ->
      unread
      |> join(:left, [m], n in Idejo.Notifications.Notification,
        on: n.message_id == m.id and n.user_id == ^user_id
      )
      |> select([m, n], %{
        count: count(m.id),
        level:
          max(
            fragment(
              "CASE ? WHEN 'mention' THEN 4 WHEN 'reply' THEN 3 WHEN 'role_mention' THEN 2 ELSE 1 END",
              n.kind
            )
          )
      })
    end

    Topic
    |> with_unread(user, summary)
    |> where([t], t.id in ^topic_ids)
    |> select([t, unread: u], {t.id, u.level})
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

    # Muted topics (steward decision, 2026-10-23) never show here.
    unread = from t in unread_topics(user), where: t.id not in subquery(muted_topic_ids(user.id))

    query =
      if Keyword.get(opts, :following, true),
        do: unread,
        else: from(t in unread, where: t.id not in subquery(followed_ids(user)))

    rows =
      Repo.all(
        from t in query,
          offset: ^((page - 1) * per_page),
          limit: ^(per_page + 1)
      )

    {rows |> Enum.take(per_page) |> with_counts(user), length(rows) > per_page}
  end

  @doc """
  Every topic the user follows (TP-13) that has unread messages, most recently active
  first, all of them: `[{topic, unread_count}]`, for the top of the Unread page (steward
  decision, 2026-10-23).
  """
  @spec list_unread_followed_topics(User.t()) :: [{Topic.t(), pos_integer()}]
  def list_unread_followed_topics(%User{} = user) do
    Repo.all(from t in unread_topics(user), where: t.id in subquery(followed_ids(user)))
    |> with_counts(user)
  end

  # The topics with unread messages in viewable categories, newest first. Each topic's first
  # unread message is enough to know (`limit: 1`, at once in the topic's index range): the
  # counts come after, for the topics shown only.
  defp unread_topics(user) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)
    any_unread = &(&1 |> select([m], %{count: 1}) |> limit(1))

    from t in with_unread(Topic, user, any_unread),
      where: t.category_id in subquery(viewable),
      order_by: [desc: t.last_activity_at, desc: t.id],
      preload: [:author, :category, tags: ^Tags.ordered()]
  end

  # Each topic with its unread count; one read meanwhile is left out.
  defp with_counts(topics, user) do
    counts = unread_counts(user, Enum.map(topics, & &1.id))
    for topic <- topics, count = counts[topic.id], do: {topic, count}
  end

  defp followed_ids(user), do: from(t in followed(user), select: t.id)

  @doc "The ids of the topics the user follows (TP-13), as a query (for `in subquery(...)`)."
  @spec followed_topic_ids(User.t()) :: Ecto.Query.t()
  def followed_topic_ids(%User{} = user), do: followed_ids(user)

  @doc """
  What is waiting for the user personally, for the badge on the header's Unread link
  (steward decision, 2026-10-23): how many unread messages reply to them, @mention them or
  +mention one of their roles, in categories they may view, and the strongest of these, as
  for the sidebar's dots (`:mention`, then `:reply`, then `:role_mention`; nil when none).
  """
  @spec for_you(User.t() | nil) :: %{count: non_neg_integer(), level: atom() | nil}
  def for_you(nil), do: %{count: 0, level: nil}

  def for_you(%User{id: user_id} = user) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    {count, level} =
      user
      |> unread_messages()
      |> join(:inner, [m], t in Topic, as: :topic, on: t.id == m.topic_id)
      |> where([topic: t], t.category_id in subquery(viewable))
      |> where([topic: t], t.id not in subquery(muted_topic_ids(user_id)))
      |> join(:inner, [m], n in Idejo.Notifications.Notification,
        as: :notification,
        on:
          n.message_id == m.id and n.user_id == ^user_id and
            n.kind in ["mention", "reply", "role_mention"]
      )
      |> select([notification: n], {
        count(n.id),
        max(fragment("CASE ? WHEN 'mention' THEN 3 WHEN 'reply' THEN 2 ELSE 1 END", n.kind))
      })
      |> Repo.one()

    %{count: count, level: level && Enum.at([:role_mention, :reply, :mention], level - 1)}
  end

  @doc """
  The user's unread notifications of `kind` ("reply", "mention" or "role_mention"), as
  `Idejo.Push.Payload` counts them (PN-01 to PN-03): on unread messages, in categories they
  may view, not in muted topics; only in `topic_id` when given. `%{count: n, titles: [...]}`,
  with the titles of up to three of their topics, the latest first.
  """
  @spec unread_notified(User.t(), String.t(), Ecto.UUID.t() | nil) :: %{
          count: non_neg_integer(),
          titles: [String.t()]
        }
  def unread_notified(%User{id: user_id} = user, kind, topic_id \\ nil) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    query =
      user
      |> unread_messages()
      |> join(:inner, [m], t in Topic, as: :topic, on: t.id == m.topic_id)
      |> where([topic: t], t.category_id in subquery(viewable))
      |> where([topic: t], t.id not in subquery(muted_topic_ids(user_id)))
      |> join(:inner, [m], n in Idejo.Notifications.Notification,
        as: :notification,
        on: n.message_id == m.id and n.user_id == ^user_id and n.kind == ^kind
      )
      |> then(&if(topic_id, do: where(&1, [m], m.topic_id == ^topic_id), else: &1))

    count = query |> select([notification: n], count(n.id)) |> Repo.one()

    titles =
      query
      |> group_by([topic: t], [t.id, t.title])
      |> order_by([m], desc: max(m.opened_at))
      |> limit(3)
      |> select([topic: t], t.title)
      |> Repo.all()

    %{count: count, titles: titles}
  end

  @doc """
  The topics with unread messages the user was notified of as a follower (`follow` rows:
  not mentions or replies, PN-05), in categories they may view, not muted, for PN-04:
  `[{topic_id, latest}]`, `latest` when the newest of those notifications was made.
  """
  @spec unread_followed(User.t()) :: [{Ecto.UUID.t(), DateTime.t()}]
  def unread_followed(%User{id: user_id} = user) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    user
    |> unread_messages()
    |> join(:inner, [m], t in Topic, as: :topic, on: t.id == m.topic_id)
    |> where([topic: t], t.category_id in subquery(viewable))
    |> where([topic: t], t.id not in subquery(muted_topic_ids(user_id)))
    |> join(:inner, [m], n in Idejo.Notifications.Notification,
      as: :notification,
      on: n.message_id == m.id and n.user_id == ^user_id and n.kind == "follow"
    )
    |> group_by([m], m.topic_id)
    |> select([m, notification: n], {m.topic_id, max(n.created_at)})
    |> Repo.all()
  end

  # Each of `topics` that has unread messages, with a summary of them as named binding
  # `:unread`: `summary` selects it from the topic's unread messages (`m`), including their
  # `count`. Also bound: `:position` (the user's read position, if any) and `:last` (its
  # message). The messages are read topic by topic, in the topic's own index range
  # (messages' topic_id, opened_at), so read messages are never touched however long the
  # topic. A lateral join that sums them up: the database cannot know beforehand how far each
  # topic was read, and given a plain join (or a subquery it may flatten into one) it reads
  # every message of the topics and filters them.
  defp with_unread(topics, %User{id: user_id, created_at: signed_up}, summary) do
    unread =
      from m in Message,
        where: m.topic_id == parent_as(:topic).id,
        where: m.author_id != ^user_id and is_nil(m.deleted_at),
        where:
          m.opened_at >
            coalesce(
              parent_as(:last).opened_at,
              coalesce(parent_as(:position).updated_at, type(^signed_up, :utc_datetime_usec))
            )

    from t in topics,
      as: :topic,
      left_join: rp in ReadPosition,
      as: :position,
      on: rp.topic_id == t.id and rp.user_id == ^user_id,
      left_join: last in Message,
      as: :last,
      on: last.id == rp.last_read_message_id,
      inner_lateral_join: u in subquery(summary.(unread)),
      as: :unread,
      on: true,
      where: u.count > 0
  end

  defp count_unread(unread), do: select(unread, [m], %{count: count(m.id)})

  # Messages by others opened after the user's read position in their topic, or after the
  # user signed up where they have none. For queries led by the user's notifications (few
  # rows); those led by topics use with_unread/3.
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
