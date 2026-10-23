# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Notifications do
  @moduledoc """
  In-app notifications (NO-01, NO-02; in-app only in v0.1). They are shown as the sidebar's
  dots on followed topics (`Idejo.Reading.activity/2`); there is no notifications page
  (steward decision, 2026-10-23), so `read_at` is no longer set.

  A new message notifies, once each: the users it @mentions (`mention`), the author of the
  message it replies to (TP-08, `reply`), the members of the roles it +mentions (TP-10, when
  its author may notify them, `role_mention`; steward decision, 2026-10-23) and the topic's
  followers (TP-13, steward decision, `follow`), never its author and never someone who may
  not view the topic. Someone in several of these gets one notification, of the first kind
  in that order. An @mentioned user, or a member of a +mentioned role, who may view the topic
  also follows it, unless they unfollowed it before (steward decisions, 2026-10-22 and
  2026-10-23).

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
end
