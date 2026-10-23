# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Notifications do
  @moduledoc """
  In-app notifications (NO-01, NO-02; in-app only in v0.1).

  A new message notifies, once each: the users it @mentions (`mention`), the author of the
  message it replies to (TP-08, `reply`), the members of the roles it +mentions (TP-10, when
  its author may notify them, `role_mention`; steward decision, 2026-10-23) and the topic's
  followers (TP-13, steward decision, `follow`), never its author and never someone who may
  not view the topic. Someone in several of these gets one notification, of the first kind
  in that order. An @mentioned user, or a member of a +mentioned role, who may view the topic
  also follows it, unless they unfollowed it before (steward decisions, 2026-10-22 and
  2026-10-23).

  Reactions (TP-17) notify the message's author once per message (`Idejo.Reactions`).

  A growing message notifies once, when it opens (NO-02, GM-13): an append, or an edit,
  notifies only someone newly mentioned. Their earlier notification for that message becomes
  the mention, unread again, when the mention ranks higher, so it stays one item.

  Both are called inside the transaction that writes the message.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Topic}
  alias Idejo.Messages.{Body, Message}
  alias Idejo.Notifications.Notification
  alias Idejo.Reading.Follow
  alias Idejo.Repo

  @doc "Notifies for a message just posted or opened in `topic`."
  @spec notify_new(Message.t(), Topic.t()) :: {:ok, non_neg_integer()}
  def notify_new(%Message{} = message, %Topic{} = topic) do
    {mentioned, role_members} = mentioned(message, topic)
    replied = replied_author(message)
    followers = followers(topic.id)

    kinds =
      Map.new(followers, &{&1, "follow"})
      |> Map.merge(Map.new(role_members, &{&1, "role_mention"}))
      |> Map.merge(Map.new(List.wrap(replied), &{&1, "reply"}))
      |> Map.merge(Map.new(mentioned, &{&1, "mention"}))
      |> Map.delete(message.author_id)

    now = DateTime.utc_now()

    rows =
      for user_id <- may_view(Map.keys(kinds), topic) do
        %{
          id: Ecto.UUID.generate(version: 7),
          user_id: user_id,
          message_id: message.id,
          kind: kinds[user_id],
          created_at: now,
          updated_at: now
        }
      end

    {count, _} =
      Repo.insert_all(Notification, rows,
        on_conflict: :nothing,
        conflict_target: [:user_id, :message_id]
      )

    {:ok, count}
  end

  @doc """
  Notifies the users newly @mentioned or +role mentioned by an append to, or an edit of, a
  message in `topic`.
  """
  @spec notify_mentions(Message.t(), Topic.t()) :: {:ok, non_neg_integer()}
  def notify_mentions(%Message{} = message, %Topic{} = topic) do
    {mentioned, role_members} = mentioned(message, topic)
    mentioned = List.delete(mentioned, message.author_id)
    role_members = (role_members -- mentioned) |> List.delete(message.author_id)

    # Already notified of this message: the mention replaces only a weaker kind.
    {users, _} =
      insert_mentions(mentioned, "mention", ~w(reply role_mention follow), topic, message)

    {members, _} = insert_mentions(role_members, "role_mention", ~w(follow), topic, message)

    {:ok, users + members}
  end

  defp insert_mentions(user_ids, kind, weaker, topic, message) do
    now = DateTime.utc_now()

    rows =
      for user_id <- may_view(user_ids, topic) do
        %{
          id: Ecto.UUID.generate(version: 7),
          user_id: user_id,
          message_id: message.id,
          kind: kind,
          created_at: now,
          updated_at: now
        }
      end

    upgrade =
      from n in Notification,
        where: n.kind in ^weaker,
        update: [set: [kind: ^kind, read_at: nil, updated_at: ^now]]

    Repo.insert_all(Notification, rows,
      on_conflict: upgrade,
      conflict_target: [:user_id, :message_id]
    )
  end

  # The users the message mentions: `{@users, members of the +roles its author may notify}`.
  # Both follow the topic when they may view it (+roles too: steward decision, 2026-10-23),
  # so it shows on their sidebar; an explicit unfollow stays.
  defp mentioned(message, topic) do
    users =
      message.body_md
      |> Body.mentioned_users()
      |> Enum.map(& &1.id)
      |> List.delete(message.author_id)

    role_members =
      message.body_md
      |> Body.mentioned_role_members(Body.context(message))
      |> List.delete(message.author_id)

    for user_id <- may_view(Enum.uniq(users ++ role_members), topic),
        do: Idejo.Reading.auto_follow(user_id, topic.id)

    {users, role_members}
  end

  defp replied_author(%Message{reply_to_id: nil}), do: nil

  defp replied_author(%Message{reply_to_id: id}),
    do: Repo.one(from m in Message, where: m.id == ^id, select: m.author_id)

  defp followers(topic_id),
    do:
      Repo.all(
        from f in Follow, where: f.topic_id == ^topic_id and f.following, select: f.user_id
      )

  # The users, among those ids, who may view the topic's category and still have an account.
  defp may_view([], _topic), do: []

  defp may_view(user_ids, topic) do
    category = Repo.get!(Category, topic.category_id)

    from(u in User, where: u.id in ^user_ids and u.status == "active")
    |> Repo.all()
    |> Enum.filter(&Access.can?(&1, :view, category))
    |> Enum.map(& &1.id)
  end

  @doc "The number of unread notifications the user may still see."
  @spec unread_count(User.t() | nil) :: non_neg_integer()
  def unread_count(nil), do: 0

  def unread_count(%User{} = user) do
    user |> visible() |> where([n], is_nil(n.read_at)) |> Repo.aggregate(:count)
  end

  @doc """
  The user's notifications, unread first, then newest, 30 a page: `{notifications, more?}`.
  Each comes with its message, the message's author and topic. Notifications for topics the
  user may no longer view are left out.
  """
  @spec list(User.t(), keyword()) :: {[Notification.t()], boolean()}
  def list(%User{} = user, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 30)
    page = max(Keyword.get(opts, :page, 1), 1)

    rows =
      user
      |> visible()
      |> order_by([n], desc: is_nil(n.read_at), desc: n.updated_at, desc: n.id)
      |> offset(^((page - 1) * per_page))
      |> limit(^(per_page + 1))
      |> preload(message: [:author, :topic])
      |> Repo.all()
      |> put_reaction_counts()

    {Enum.take(rows, per_page), length(rows) > per_page}
  end

  @doc """
  Marks one of the user's notifications read and returns it with its message, or `nil` when
  it is not theirs or no longer visible to them.
  """
  @spec open(User.t(), String.t()) :: Notification.t() | nil
  def open(%User{} = user, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Notification{} = notification <-
           user |> visible() |> where([n], n.id == ^id) |> preload(:message) |> Repo.one() do
      if notification.read_at,
        do: notification,
        else: notification |> Ecto.Changeset.change(read_at: DateTime.utc_now()) |> Repo.update!()
    else
      _ -> nil
    end
  end

  # TP-17: a reaction notification says how many reactions the message has now.
  defp put_reaction_counts(rows) do
    counts =
      rows
      |> Enum.filter(&(&1.kind == "reaction"))
      |> Enum.map(& &1.message_id)
      |> Idejo.Reactions.counts()

    Enum.map(rows, &%{&1 | reactions: Map.get(counts, &1.message_id, 0)})
  end

  @doc "Marks all the user's notifications read."
  @spec mark_all_read(User.t()) :: :ok
  def mark_all_read(%User{id: user_id}) do
    Repo.update_all(
      from(n in Notification, where: n.user_id == ^user_id and is_nil(n.read_at)),
      set: [read_at: DateTime.utc_now()]
    )

    :ok
  end

  defp visible(%User{id: user_id} = user) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    from n in Notification,
      join: m in assoc(n, :message),
      join: t in Topic,
      on: t.id == m.topic_id,
      where: n.user_id == ^user_id and t.category_id in subquery(viewable),
      # MO-02: nothing about a message a moderator deleted.
      where: is_nil(m.deleted_at)
  end
end
