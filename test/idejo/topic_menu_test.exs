# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The topic menu's "Unfollow & mute" and "Mark unread" (steward decision, 2026-10-23): no
# requirement ID.
defmodule Idejo.TopicMenuTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Notifications.Notification
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture(%{username: unique_username("ada"), display_name: "Ada"})
    bo = user_fixture(%{username: unique_username("bo"), display_name: "Bo"})
    {:ok, topic} = Forum.create_topic(ada, general, %{"title" => "Plans", "body" => "Tonight?"})

    %{admin: admin, ada: ada, bo: bo, topic: topic}
  end

  defp notifications(user),
    do: Repo.all(from n in Notification, where: n.user_id == ^user.id, select: n.kind)

  test "a muted topic notifies nothing, mentions and replies included, until followed again", %{
    admin: admin,
    ada: ada,
    bo: bo,
    topic: topic
  } do
    {:ok, mine} = Forum.post_message(bo, topic, %{"body" => "Count me in"})
    :ok = Reading.mute(bo, topic)
    refute Reading.following?(bo, topic)

    role = Access.built_in_role!(:moderator)
    {:ok, _} = Access.assign_role(admin, bo, role)

    {:ok, _} =
      Forum.post_message(ada, topic, %{
        "body" => "@#{bo.username} +moderator see this",
        "reply_to_id" => mine.id
      })

    assert notifications(bo) == []
    # Posting or a mention does not follow it again, and it is off the Unread page and count.
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Hm"})
    refute Reading.following?(bo, topic)
    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "@#{bo.username} again"})
    assert Reading.for_you(bo).count == 0
    assert {[], false} = Reading.list_unread_topics(bo)

    # Following again lifts the mute.
    :ok = Reading.follow(bo, topic)
    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "@#{bo.username} back?"})
    assert "mention" in notifications(bo)
    assert Reading.for_you(bo).count > 0
  end

  test "mark unread makes the latest message by someone else new again", %{
    ada: ada,
    bo: bo,
    topic: topic
  } do
    # Only the opening message, by someone else: the whole topic is unread.
    Reading.mark_read(bo, topic)
    assert Reading.unread_counts(bo, [topic.id]) == %{}
    :ok = Reading.mark_unread(bo, topic)
    assert Reading.unread_counts(bo, [topic.id]) == %{topic.id => 1}

    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "One"})
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Mine"})
    {:ok, last} = Forum.post_message(ada, topic, %{"body" => "Two"})
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Mine again"})
    Reading.mark_read(bo, topic)

    :ok = Reading.mark_unread(bo, topic)
    assert Reading.unread_counts(bo, [topic.id]) == %{topic.id => 1}
    assert %{id: id, count: 1} = Reading.first_unread(bo, topic)
    assert id == last.id

    # Nobody else wrote: nothing changes.
    {:ok, alone} =
      Forum.create_topic(bo, Repo.preload(topic, :category).category, %{
        "title" => "Mine",
        "body" => "Alone"
      })

    :ok = Reading.mark_unread(bo, alone)
    assert Reading.unread_counts(bo, [alone.id]) == %{}
  end
end
