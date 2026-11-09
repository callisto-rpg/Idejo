# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules out of the web layer (AP-01 preparation): private conversations (steward decision,
# 2026-10-27), asked of the contexts directly with what a client could send. Whoever is not
# a participant gets nothing, administrators included.
defmodule Idejo.ConversationsRulesTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Conversations
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.Polls
  alias Idejo.Moderation
  alias Idejo.Reactions

  setup do
    alice = user_fixture()
    bob = user_fixture()
    {:ok, topic} = Conversations.start(alice, bob.id)
    {:ok, message} = Messages.commit(alice, topic, "Just us", break: true)
    %{alice: alice, bob: bob, topic: topic, message: message}
  end

  test "start/2 takes the recipient's id, and refuses an unknown one", %{alice: alice, bob: bob} do
    assert {:ok, topic} = Conversations.start(bob, alice.id)
    assert Conversations.participant?(alice, topic)

    for id <- [Ecto.UUID.generate(), "not an id"],
        do: assert({:error, :forbidden} = Conversations.start(alice, id))

    assert {:error, :forbidden} = Conversations.start(alice, alice.id)
  end

  test "start/2 refuses an unverified or banned sender, and a recipient who takes none", %{
    alice: alice
  } do
    admin = user_with_role_fixture(:administrator)
    banned = user_fixture()
    {:ok, {banned, _sessions}} = Accounts.ban_for(admin, banned, :forever)

    assert {:error, :forbidden} = Conversations.start(unconfirmed_user_fixture(), alice.id)
    assert {:error, :forbidden} = Conversations.start(banned, alice.id)

    {:ok, closed} =
      Accounts.update_user_private_messages(user_fixture(), %{"accepts_private_messages" => false})

    assert {:error, :forbidden} = Conversations.start(alice, closed.id)
  end

  test "someone else reads, writes, reacts or reports nothing there, an administrator neither",
       %{topic: topic, message: message} do
    for outsider <- [user_fixture(), user_with_role_fixture(:administrator), nil] do
      assert Conversations.get(outsider, topic.id) == nil
      assert Forum.get_readable_topic(outsider, topic.id) == nil
      assert Forum.get_readable_message(outsider, message.id) == nil
      refute Forum.can_post?(outsider, topic)
      assert Reactions.reactors(outsider, message.id) == []
    end

    outsider = user_fixture()
    assert {:error, :forbidden} = Messages.commit(outsider, topic, "Hello?")
    assert {:error, :forbidden} = Reactions.toggle(outsider, message, "heart")
    assert {:error, :forbidden} = Moderation.report_message(outsider, message, %{"reason" => "x"})
    assert Moderation.get_reportable_message(outsider, message.id) == nil

    poll = %{"question" => "Which?", "options" => ["A", "B"], "hours" => "1"}
    assert {:error, :forbidden} = Polls.create(outsider, message.id, poll)
  end

  @tag req: "MO-01"
  test "MO-01 a participant reports, and only a server moderator deletes from the queue", %{
    bob: bob,
    message: message
  } do
    assert {:ok, _report} = Moderation.report_message(bob, message, %{"reason" => "rude"})

    assert {:error, :forbidden} = Messages.delete_reported_private(user_fixture(), message)
    assert {:error, :forbidden} = Messages.delete_reported_private(bob, message)

    admin = user_with_role_fixture(:administrator)
    assert {:ok, %{deleted_at: %DateTime{}}} = Messages.delete_reported_private(admin, message)
  end

  test "a conversation is never forked, and has no window", %{alice: alice, topic: topic} do
    refute Forum.can_fork?(alice, topic)
    assert Messages.window_seconds(topic) == 0
  end
end
