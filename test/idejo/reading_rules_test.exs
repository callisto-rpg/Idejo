# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules out of the web layer (AP-01 preparation): following, muting and marking unread by a
# topic id from a client, who reacted, and who may react, asked of the contexts directly.
defmodule Idejo.ReadingRulesTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Conversations
  alias Idejo.Forum
  alias Idejo.Reactions
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, hidden} = Forum.create_category(admin, %{"name" => "Staff"})

    for role <- Access.list_roles(),
        role.name in ~w(member guest),
        do: {:ok, _} = Access.set_permission(admin, role, hidden, :view, :deny)

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    {:ok, secret} = Forum.create_topic(admin, hidden, %{"title" => "Secret", "body" => "Staff"})

    %{admin: admin, topic: topic, secret: secret}
  end

  @tag req: "TP-13"
  test "TP-13 act_on_topic/3 follows, unfollows, mutes and marks unread a viewable topic", %{
    topic: topic
  } do
    member = user_fixture()

    for action <- [:follow, :unfollow, :mute, :mark_unread] do
      assert {:ok, %{id: id}} = Reading.act_on_topic(member, action, topic.id)
      assert id == topic.id
    end

    {:ok, _} = Reading.act_on_topic(member, :follow, topic.id)
    assert Reading.following?(member, topic)
  end

  @tag req: "TP-13"
  test "TP-13 act_on_topic/3 refuses a topic the user may not view, a private one or a bad id",
       %{topic: topic, secret: secret} do
    member = user_fixture()
    {:ok, private} = Conversations.start(user_fixture(), user_fixture())

    for id <- [secret.id, private.id, Ecto.UUID.generate(), "not an id", nil],
        action <- [:follow, :unfollow, :mute, :mark_unread],
        do: assert({:error, :not_found} = Reading.act_on_topic(member, action, id))

    refute Reading.following?(member, secret)
    assert {:ok, _} = Reading.act_on_topic(member, :follow, topic.id)
  end

  @tag req: "TP-17"
  test "TP-17 reactors/2 shows who reacted only to a reader of the message", %{
    admin: admin,
    secret: secret
  } do
    [message] = Forum.list_messages(secret)
    {:ok, _} = Reactions.toggle(admin, message, "heart")

    assert [%{emoji: ["heart"]}] = Reactions.reactors(admin, message.id)
    assert Reactions.reactors(user_fixture(), message.id) == []
    assert Reactions.reactors(nil, message.id) == []
    assert Reactions.reactors(admin, "not an id") == []
    assert Reactions.reactors(admin, nil) == []
  end

  @tag req: "TP-17"
  test "TP-17 may_react_in?/2: verified readers, while the topic is open", %{
    admin: admin,
    topic: topic
  } do
    member = user_fixture()
    assert Reactions.may_react_in?(member, topic)
    refute Reactions.may_react_in?(nil, topic)
    refute Reactions.may_react_in?(unconfirmed_user_fixture(), topic)

    {:ok, locked} = Forum.moderate_topic(admin, topic, :lock, nil)
    refute Reactions.may_react_in?(member, locked)

    [message] = Forum.list_messages(locked)
    assert {:error, :forbidden} = Reactions.toggle(member, message, "heart")
  end

  @tag req: "TP-17"
  test "TP-17 nobody reacts to a message they may not read", %{secret: secret} do
    [message] = Forum.list_messages(secret)
    member = user_fixture()

    refute Reactions.may_react?(member, message)
    assert {:error, :forbidden} = Reactions.toggle(member, message, "heart")
  end
end
