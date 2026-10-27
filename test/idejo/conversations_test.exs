# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ConversationsTest do
  # Private conversations (steward decision, 2026-10-27).
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Conversations
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation
  alias Idejo.Notifications.Notification
  alias Idejo.Reading
  alias Idejo.Search

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{ada: user_fixture(%{display_name: "Ada"}), bo: user_fixture(%{display_name: "Bo"})}
  end

  test "one conversation per pair, which both follow", %{ada: ada, bo: bo} do
    {:ok, topic} = Conversations.start(ada, bo)
    assert topic.private and is_nil(topic.category_id)
    assert {:ok, %{id: id}} = Conversations.start(bo, ada)
    assert id == topic.id

    assert Enum.sort(Conversations.participant_ids(topic)) == Enum.sort([ada.id, bo.id])
    assert Reading.following?(ada, topic) and Reading.following?(bo, topic)
  end

  @tag req: "AC-01"
  test "AC-01 only verified members write, to someone who accepts private messages", %{
    ada: ada,
    bo: bo
  } do
    refute Conversations.may_message?(ada, ada)
    refute Conversations.may_message?(nil, bo)
    refute Conversations.may_message?(unconfirmed_user_fixture(), bo)
    assert Conversations.start(ada, ada) == {:error, :forbidden}

    {:ok, topic} = Conversations.start(ada, bo)
    assert Forum.can_post?(ada, topic) and Forum.can_post?(bo, topic)
    refute Forum.can_post?(user_fixture(), topic)

    # Bo turns them off: nobody starts one with Bo or writes to Bo, but Bo may still write.
    {:ok, bo} =
      Accounts.update_user_private_messages(bo, %{"accepts_private_messages" => "false"})

    refute Conversations.may_message?(ada, bo)
    assert Conversations.start(user_fixture(), bo) == {:error, :forbidden}
    refute Forum.can_post?(ada, topic)
    assert Forum.can_post?(bo, topic)
  end

  test "only participants read it, owners and administrators included", %{ada: ada, bo: bo} do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, message} = Messages.commit(ada, topic, "a secret word: xylophone", break: true)

    for outsider <- [nil, user_fixture(), user_with_role_fixture(:administrator)] do
      assert Forum.get_viewable_topic(outsider, topic.id) == nil
      assert Forum.get_readable_topic(outsider, topic.id) == nil
      assert Forum.get_readable_message(outsider, message.id) == nil
      assert Conversations.get(outsider, topic.id) == nil
    end

    assert Forum.get_readable_topic(bo, topic.id).id == topic.id
    assert Forum.get_readable_message(bo, message.id).id == message.id
    # Every list goes through categories, so none holds it.
    assert Forum.get_viewable_topic(bo, topic.id) == nil
    refute Access.can?(user_with_role_fixture(:owner), :view, nil)
    assert Reading.list_followed_topics(bo) == []
    assert {[], _} = Search.search(user_with_role_fixture(:administrator), "xylophone")
    assert {[], _} = Search.search(bo, "xylophone")
  end

  @tag req: "GM-05"
  test "GM-05 no slow mode: Ctrl+Enter starts a new message at once", %{ada: ada, bo: bo} do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, first} = Messages.commit(ada, topic, "Hello")
    assert first.state == "open"
    assert Messages.no_window?(first)
    assert Messages.may_start_new?(first)

    {:ok, closed} = Messages.commit(ada, topic, "Hello", break: true)
    assert closed.id == first.id and closed.state == "closed"

    # A topic's messages keep their window.
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, public} = Forum.create_topic(bo, general, %{"title" => "Hi", "body" => "Hi"})
    {:ok, open} = Messages.commit(ada, public, "Hello")
    refute Messages.no_window?(open)
  end

  @tag req: "NO-01"
  test "NO-01 only participants are notified", %{ada: ada, bo: bo} do
    outsider = user_fixture()
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, message} = Messages.commit(ada, topic, "Hi @#{outsider.username}", break: true)

    assert [%{user_id: user_id}] =
             Repo.all(from n in Notification, where: n.message_id == ^message.id)

    assert user_id == bo.id
  end

  @tag req: "MO-01"
  test "MO-01 a participant reports a message; server moderators see only that message", %{
    ada: ada,
    bo: bo
  } do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, message} = Messages.commit(ada, topic, "rude words", break: true)

    assert Moderation.report_message(user_fixture(), message, %{"reason" => "x"}) ==
             {:error, :forbidden}

    {:ok, _report} = Moderation.report_message(bo, message, %{"reason" => "Rude"})

    # A category moderator does not see it; a server moderator does.
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Helpers")})
    {:ok, _} = Access.set_permission(admin, role, general, :moderate, :allow)
    helper = user_fixture()
    :ok = Access.grant_role(helper, role)
    moderator = user_with_role_fixture(:moderator)

    assert Moderation.list_open_reports(helper) == []
    assert Moderation.get_reported_message(helper, message.id) == nil
    assert [%{message: %{id: id}}] = Moderation.list_open_reports(moderator)
    assert id == message.id

    # The message, never the conversation.
    assert Forum.get_readable_topic(moderator, topic.id) == nil
    assert Moderation.handle_reports(helper, message, :dismiss) == {:error, :forbidden}
    reported = Moderation.get_reported_message(moderator, message.id)
    assert {:ok, 1} = Moderation.handle_reports(moderator, reported, :resolve)
    assert Moderation.get_reported_message(moderator, message.id) == nil
  end

  @tag req: "MO-02"
  test "MO-02 a server moderator deletes a reported private message, and only that", %{
    ada: ada,
    bo: bo
  } do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, message} = Forum.post_message(ada, topic, %{"body" => "rude words"})
    {:ok, other} = Forum.post_message(ada, topic, %{"body" => "not reported"})
    moderator = user_with_role_fixture(:moderator)

    # Nothing reported: nothing to delete.
    assert Messages.delete_reported_private(moderator, message) == {:error, :forbidden}

    {:ok, _report} = Moderation.report_message(bo, message, %{"reason" => "Rude"})

    for nobody <- [user_fixture(), bo] do
      assert Messages.delete_reported_private(nobody, message) == {:error, :forbidden}
    end

    assert Messages.delete_reported_private(moderator, other) == {:error, :forbidden}

    assert {:ok, %{deleted_at: %DateTime{}, deleted_by_id: by}} =
             Messages.delete_reported_private(moderator, message, "Insults")

    assert by == moderator.id
    assert Moderation.list_open_reports(moderator) == []

    assert [%{action: "message.delete", reason: "Insults"}] =
             Repo.all(Idejo.Moderation.Action)

    # A topic's message goes through the category's moderators, not this.
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, public} = Forum.create_topic(bo, general, %{"title" => "Hi", "body" => "Hi"})
    {:ok, reply} = Forum.post_message(bo, public, %{"body" => "Rude"})
    {:ok, _} = Moderation.report_message(ada, reply, %{"reason" => "Rude"})
    assert Messages.delete_reported_private(moderator, reply) == {:error, :forbidden}
  end

  test "the list holds the user's conversations, with the last message and unread", %{
    ada: ada,
    bo: bo
  } do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "First"})
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Second"})

    assert [%{topic: %{id: id}, others: [other], last: last, unread: 2}] = Conversations.list(ada)
    assert id == topic.id and other.id == bo.id
    assert last.body_md == "Second"
    assert Conversations.unread_count(ada) == 1
    assert Conversations.unread_count(bo) == 0
    assert Conversations.list(user_fixture()) == []
  end
end
