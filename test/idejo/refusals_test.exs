# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules live in contexts (AP-01 preparation): what a member does to a topic is refused by the
# context itself, whoever calls it, in each situation a later API will meet. Without the
# post right, in a locked topic and in an archived one, every action is refused with
# `{:error, :forbidden}`; moderator actions refuse a plain member; a banned account never
# becomes an actor; a visitor (nil) cannot call an action at all.
defmodule Idejo.RefusalsTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.{Automessages, Polls, Scheduling}
  alias Idejo.Moderation.Warnings
  alias Idejo.Reactions

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, category} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, other} = Forum.create_category(admin, %{"name" => "Elsewhere"})
    member = user_fixture()
    {:ok, topic} = Forum.create_topic(member, category, %{"title" => "Mine", "body" => "Hello"})
    [opening] = Forum.list_messages(topic)
    {:ok, own} = Forum.post_message(member, topic, %{"body" => "Mine too"})
    {:ok, theirs} = Forum.post_message(user_fixture(), topic, %{"body" => "Someone else"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{
      admin: admin,
      category: category,
      other: other,
      member: member,
      topic: topic,
      opening: opening,
      own: own,
      theirs: theirs
    }
  end

  # What a member may do in a topic they may post in.
  defp member_actions(member, topic, own, theirs) do
    poll = %{"question" => "Which?", "options" => ["A", "B"], "hours" => "1"}

    [
      commit: fn -> Messages.commit(member, topic, "More") end,
      post_message: fn -> Forum.post_message(member, topic, %{"body" => "More"}) end,
      edit: fn -> Messages.edit(member, own, "Changed") end,
      delete_own: fn -> Messages.delete_own(member, own) end,
      spoiler: fn -> Messages.set_spoiler(member, own, true) end,
      poll: fn -> Polls.create(member, own.id, poll) end,
      poll_post: fn -> Polls.post(member, topic, poll) end,
      schedule: fn -> Scheduling.schedule(member, topic, "Later", 3600) end,
      react: fn -> Reactions.toggle(member, theirs, "heart") end,
      automessage: fn -> Automessages.post(member, topic, "rules") end,
      rename: fn -> Forum.rename_topic(member, topic, "Renamed") end
    ]
  end

  defp assert_all_refused(actions) do
    for {name, action} <- actions do
      assert action.() == {:error, :forbidden}, "#{name} was not refused"
    end
  end

  test "without the post right, every member action is refused", ctx do
    member_role = Enum.find(Access.list_roles(), &(&1.name == "member"))
    {:ok, _} = Access.set_permission(ctx.admin, member_role, ctx.category, :post, :deny)
    topic = Repo.reload!(ctx.topic)

    # Reacting needs only the view right (TP-17), so it stays allowed here.
    ctx.member
    |> member_actions(topic, ctx.own, ctx.theirs)
    |> Keyword.delete(:react)
    |> assert_all_refused()
  end

  @tag req: "TP-14"
  test "TP-14 in a locked topic, every member action is refused", ctx do
    {:ok, locked} = Forum.moderate_topic(ctx.admin, ctx.topic, :lock, nil)
    assert_all_refused(member_actions(ctx.member, locked, ctx.own, ctx.theirs))
  end

  @tag req: "AD-03"
  test "AD-03 in an archived topic, every member action is refused", ctx do
    {:ok, archived} = Forum.archive_topic(ctx.admin, ctx.topic, nil)
    assert_all_refused(member_actions(ctx.member, archived, ctx.own, ctx.theirs))
  end

  @tag req: "MO-02"
  test "MO-02 moderator actions refuse a plain member", ctx do
    %{member: member, topic: topic, theirs: theirs, other: other} = ctx

    assert_all_refused(
      lock: fn -> Forum.moderate_topic(member, topic, :lock, nil) end,
      pin: fn -> Forum.moderate_topic(member, topic, :pin, nil) end,
      move: fn -> Forum.move_topic(member, topic, other, nil) end,
      archive: fn -> Forum.archive_topic(member, topic, nil) end,
      delete_topic: fn -> Forum.delete_topic(member, topic, nil) end,
      inactive: fn -> Forum.mark_inactive(member, topic) end,
      tags: fn -> Forum.set_topic_tags(member, topic, [], nil) end,
      delete_message: fn -> Messages.delete_as_moderator(member, theirs) end,
      edit_message: fn -> Messages.edit_as_moderator(member, theirs, "Mine now") end,
      delete_many: fn -> Messages.delete_many_as_moderator(member, topic, [theirs.id]) end,
      warn: fn -> Warnings.warn(member, theirs, "Be nice") end,
      move_messages: fn ->
        Forum.move_messages(member, topic, [theirs.id], {:new, %{"title" => "X"}}, nil)
      end
    )
  end

  @tag req: "MO-02"
  test "MO-02 a banned account never becomes an actor", %{admin: admin, member: member} do
    token = Accounts.generate_user_session_token(member)
    assert {%{id: id}, _} = Accounts.get_user_by_session_token(token)
    assert id == member.id

    {:ok, {banned, _}} = Accounts.ban_for(admin, member, {:days, 7})

    # Its sessions end, no new one resolves to it, and nothing signs it in.
    assert Accounts.get_user_by_session_token(token) == nil
    assert Accounts.get_user_by_session_token(Accounts.generate_user_session_token(banned)) == nil
    assert {:error, :banned} = Accounts.may_sign_in(banned)
    assert {:error, {:banned, _}} = Accounts.authenticate(banned.email, valid_user_password())
  end

  test "a visitor reads only what guests may, and cannot call an action", ctx do
    assert Forum.get_readable_topic(nil, ctx.topic.id).id == ctx.topic.id
    refute Forum.can_post?(nil, ctx.topic)
    assert Reactions.reactors(nil, ctx.theirs.id) == []

    # Actions take a signed-in actor: a visitor matches no clause. (Through `apply/3`, as
    # the compiler already knows these calls cannot match.)
    for {module, fun, args} <- [
          {Messages, :commit, [nil, ctx.topic, "Hi"]},
          {Forum, :post_message, [nil, ctx.topic, %{}]},
          {Reactions, :toggle, [nil, ctx.theirs, "heart"]}
        ] do
      assert_raise FunctionClauseError, fn -> apply(module, fun, args) end
    end
  end
end
