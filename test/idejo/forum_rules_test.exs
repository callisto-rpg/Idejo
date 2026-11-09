# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules out of the web layer (AP-01 preparation): the topic menu, fork sources, reports,
# bans, inactive topics, topical topics and replies, asked of the contexts directly with what
# a client could send. Not async: one test changes a server-wide setting.
defmodule Idejo.ForumRulesTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, hidden} = Forum.create_category(admin, %{"name" => "Staff"})

    for role <- Access.list_roles(),
        role.name in ~w(member guest),
        do: {:ok, _} = Access.set_permission(admin, role, hidden, :view, :deny)

    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Chat", "body" => "Hi"})
    {:ok, secret} = Forum.create_topic(admin, hidden, %{"title" => "Secret", "body" => "Staff"})
    [first] = Forum.list_messages(topic)
    [hidden_first] = Forum.list_messages(secret)

    %{
      admin: admin,
      general: general,
      starter: starter,
      topic: topic,
      secret: secret,
      first: first,
      hidden_first: hidden_first
    }
  end

  @tag req: "TP-14"
  test "TP-14 topic_menu/2: for moderators of the topic's category only", %{
    admin: admin,
    topic: topic,
    secret: secret
  } do
    assert {:ok, %{archived: false, category_id: id, following: _}} =
             Forum.topic_menu(admin, topic.id)

    assert id == topic.category_id

    for user <- [user_fixture(), nil],
        id <- [topic.id, secret.id],
        do: assert({:error, :not_found} = Forum.topic_menu(user, id))

    assert {:error, :not_found} = Forum.topic_menu(admin, Ecto.UUID.generate())
    assert {:error, :not_found} = Forum.topic_menu(admin, "not an id")
    assert {:error, :not_found} = Forum.topic_menu(admin, nil)
  end

  @tag req: "TP-14"
  test "TP-14 mark_inactive/2 is refused while inactive topics are off", %{
    admin: admin,
    topic: topic
  } do
    assert {:error, :forbidden} = Forum.mark_inactive(user_fixture(), topic)
    {:ok, _} = Settings.update_settings(admin, %{"inactive_topics" => "false"})
    assert {:error, :disabled} = Forum.mark_inactive(admin, topic)
    {:ok, _} = Settings.update_settings(admin, %{"inactive_topics" => "true"})
    assert {:ok, _} = Forum.mark_inactive(admin, topic)
  end

  @tag req: "TP-09"
  test "TP-09 get_fork_source/2: a viewable message not deleted, with its author", %{
    admin: admin,
    first: first,
    hidden_first: hidden_first
  } do
    member = user_fixture()
    assert %{author: %Accounts.User{}} = Forum.get_fork_source(member, first.id)
    assert Forum.get_fork_source(member, hidden_first.id) == nil
    assert Forum.get_fork_source(member, "not an id") == nil
    assert Forum.get_fork_source(member, nil) == nil

    {:ok, reply} = Messages.commit(user_fixture(), Repo.get!(Forum.Topic, first.topic_id), "Hm")
    {:ok, _} = Messages.delete_as_moderator(admin, reply)
    assert Forum.get_fork_source(member, reply.id) == nil
  end

  @tag req: "MO-01"
  test "MO-01 get_reportable_message/2 and report_message/3: not one's own, deleted or unread",
       %{starter: starter, first: first, hidden_first: hidden_first, admin: admin} do
    member = user_fixture()
    assert %{author: %Accounts.User{}} = Moderation.get_reportable_message(member, first.id)

    assert Moderation.get_reportable_message(starter, first.id) == nil
    assert Moderation.get_reportable_message(member, hidden_first.id) == nil
    assert Moderation.get_reportable_message(member, "not an id") == nil

    reason = %{"reason" => "spam"}
    assert {:error, :forbidden} = Moderation.report_message(starter, first, reason)
    assert {:error, :forbidden} = Moderation.report_message(member, hidden_first, reason)

    {:ok, deleted} = Messages.delete_as_moderator(admin, first)
    assert {:error, :forbidden} = Moderation.report_message(member, deleted, reason)
  end

  @tag req: "MO-02"
  test "MO-02 ban_for/4 takes only the lengths moderators choose from", %{admin: admin} do
    assert {:error, :duration} = Accounts.ban_for(admin, user_fixture(), {:days, 2})
    assert {:error, :duration} = Accounts.ban_for(admin, user_fixture(), :none)
    assert {:error, :duration} = Accounts.ban_for(admin, user_fixture(), {:days, -1})

    for days <- Accounts.ban_days(),
        do: assert({:ok, _} = Accounts.ban_for(admin, user_fixture(), {:days, days}))

    assert {:ok, {banned, _}} = Accounts.ban_for(admin, user_fixture(), :forever, "Spam")
    assert banned.banned_until == nil
  end

  @tag req: "MO-02"
  test "MO-02 may_ban?/2 and ban_for/4: a server moderator, never oneself or an administrator",
       %{admin: admin} do
    member = user_fixture()
    other = user_fixture()

    assert Accounts.may_ban?(admin, member)
    refute Accounts.may_ban?(member, other)
    refute Accounts.may_ban?(nil, other)
    refute Accounts.may_ban?(admin, admin)
    refute Accounts.may_ban?(admin, user_with_role_fixture(:administrator))

    assert {:error, :forbidden} = Accounts.ban_for(member, other, :forever)
    assert {:error, :not_bannable} = Accounts.ban_for(admin, admin, :forever)
  end

  @tag req: "TP-08"
  test "TP-08 post_message/3 drops a reply to a deleted message", %{
    admin: admin,
    topic: topic
  } do
    {:ok, gone} = Forum.post_message(user_fixture(), topic, %{"body" => "Soon gone"})
    {:ok, _} = Messages.delete_as_moderator(admin, gone)

    {:ok, reply} =
      Forum.post_message(user_fixture(), topic, %{"body" => "To it", "reply_to_id" => gone.id})

    assert reply.reply_to_id == nil
  end

  @tag req: "RP-04"
  test "RP-04 may_post_topical?/2: moderators of a user category", %{
    admin: admin,
    general: general
  } do
    assert Forum.may_post_topical?(admin, general)
    refute Forum.may_post_topical?(user_fixture(), general)
    refute Forum.may_post_topical?(nil, general)

    {:ok, topical} =
      Forum.create_category(admin, %{"name" => "Places", "topic_type" => "topical"})

    refute Forum.may_post_topical?(admin, topical)
  end
end
