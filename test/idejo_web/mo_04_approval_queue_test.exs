# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MO04ApprovalQueueTest do
  @moduledoc """
  MO-04: a category takes new topics openly, after a moderator's approval (every one, or new
  users' only), or not at all. Waiting topics are seen by their author and by the category's
  moderators, who approve or reject them from the Moderation screen.
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Forum.{PendingTopic, Topic}
  alias Idejo.Moderation.Action
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, other} = Forum.create_category(admin, %{"name" => "Other"})
    member = user_fixture(%{display_name: "Newcomer"})
    %{admin: admin, general: general, other: other, member: member}
  end

  defp set_mode(admin, category, mode) do
    {:ok, category} = Forum.update_category(admin, category, %{"new_topics" => mode})
    category
  end

  defp category_moderator(admin, category) do
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Mods")})
    {:ok, _} = Access.set_permission(admin, role, category, :moderate, :allow)
    user = user_fixture()
    {:ok, _} = Access.assign_role(admin, user, role)
    user
  end

  defp start(user, category, title),
    do: Forum.create_topic(user, category, %{"title" => title, "body" => "Body of #{title}"})

  @tag req: "MO-04"
  test "MO-04 open: topics start at once; closed: only moderators start them", %{
    admin: admin,
    general: general,
    member: member
  } do
    assert {:ok, %Topic{}} = start(member, general, "Open")

    closed = set_mode(admin, general, "closed")
    refute Forum.can_start_topic?(member, closed)
    assert start(member, closed, "Shut") == {:error, :forbidden}
    refute closed.id in Enum.map(Forum.list_startable_categories(member), & &1.id)

    mod = category_moderator(admin, closed)
    assert {:ok, %Topic{}} = start(mod, closed, "From a moderator")
    assert {:ok, %Topic{}} = start(admin, closed, "From an administrator")
  end

  @tag req: "MO-04"
  test "MO-04 approval: every topic waits, hidden from lists, until approved; logged", %{
    admin: admin,
    general: general,
    other: other,
    member: member
  } do
    general = set_mode(admin, general, "approval")
    mod = category_moderator(admin, general)
    other_mod = category_moderator(admin, other)

    assert {:pending, %PendingTopic{} = pending} = start(member, general, "Waiting")
    refute Repo.exists?(from t in Topic, where: t.title == "Waiting")
    assert {[], false} = Forum.list_topics(general)
    assert Forum.list_own_pending_topics(member, general) |> Enum.map(& &1.id) == [pending.id]
    assert Forum.list_own_pending_topics(user_fixture(), general) == []

    # Moderators of the category (and administrators) see it; others do not.
    assert Enum.map(Forum.list_pending_topics(mod), & &1.id) == [pending.id]
    assert Forum.pending_topic_count(admin) == 1
    assert Forum.list_pending_topics(other_mod) == []
    assert Forum.approve_topic(other_mod, pending) == {:error, :forbidden}

    # Its moderators' own topics never wait.
    assert {:ok, %Topic{}} = start(mod, general, "Mine")

    assert {:ok, topic} = Forum.approve_topic(mod, pending)
    assert topic.title == "Waiting"
    assert topic.author_id == member.id
    assert Repo.get(PendingTopic, pending.id) == nil
    assert Repo.get_by!(Action, action: "topic.approve").target_id == topic.id
    assert Forum.approve_topic(mod, pending) == {:error, :not_found}

    # Every topic waits under "approval", even from someone not new.
    assert {:pending, _} = start(member, general, "Again")
  end

  @tag req: "MO-04"
  test "MO-04 new users: only a user's topics before their first one wait", %{
    admin: admin,
    general: general,
    other: other,
    member: member
  } do
    general = set_mode(admin, general, "new_users")
    assert Forum.new_user?(member)
    assert {:pending, pending} = start(member, general, "First")
    {:ok, _} = Forum.approve_topic(admin, pending)

    refute Forum.new_user?(member)
    assert {:ok, %Topic{}} = start(member, general, "Second")

    # A user who started a topic elsewhere is not new either.
    veteran = user_fixture()
    {:ok, _} = start(veteran, other, "Elsewhere")
    assert {:ok, %Topic{}} = start(veteran, general, "Here")
  end

  @tag req: "MO-04"
  test "MO-04 rejecting deletes the topic and logs its title with the reason", %{
    admin: admin,
    general: general,
    member: member
  } do
    general = set_mode(admin, general, "approval")
    mod = category_moderator(admin, general)
    {:pending, pending} = start(member, general, "Spam")

    assert {:ok, _} = Forum.reject_topic(mod, pending, "Advertising")
    assert Repo.get(PendingTopic, pending.id) == nil
    refute Repo.exists?(from t in Topic, where: t.title == "Spam")

    entry = Repo.get_by!(Action, action: "topic.reject")
    assert entry.target_id == member.id
    assert entry.category_id == general.id
    assert entry.reason == "Advertising"
    assert entry.details == %{"title" => "Spam"}
  end

  @tag req: "MO-04"
  test "MO-04 the pages: sent, shown to its author, approved from Moderation", %{
    conn: conn,
    admin: admin,
    general: general,
    member: member
  } do
    general = set_mode(admin, general, "approval")
    mod = category_moderator(admin, general)

    member_conn = log_in_user(conn, member)
    {:ok, lv, _html} = live(member_conn, ~p"/c/#{general.slug}/new")

    {:ok, sent} =
      lv
      |> form("#new-topic-form", topic: %{title: "Hello all", body: "First words"})
      |> render_submit()
      |> follow_redirect(member_conn, ~p"/c/#{general.slug}")

    page = html_response(sent, 200)
    assert page =~ "once a moderator approves it"
    assert page =~ ~s(id="own-pending")
    assert page =~ "Hello all"
    refute build_conn() |> get(~p"/c/#{general.slug}") |> html_response(200) =~ "Hello all"

    mod_conn = log_in_user(build_conn(), mod)
    queue = mod_conn |> get(~p"/moderation") |> html_response(200)
    [pending] = Forum.list_pending_topics(mod)
    assert queue =~ ~s(id="pending-#{pending.id}")
    assert queue =~ "First words"
    assert queue =~ ~s(id="pending-topics-badge")

    conn = post(mod_conn, ~p"/moderation/topics/#{pending.id}", %{"outcome" => "approve"})
    assert redirected_to(conn) == ~p"/moderation"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Topic approved"
    assert Repo.exists?(from t in Topic, where: t.title == "Hello all")

    # Someone who may not moderate the category gets nothing.
    {:pending, again} = start(member, general, "Second try")
    outsider = log_in_user(build_conn(), user_fixture())

    assert_error_sent 404, fn ->
      post(outsider, ~p"/moderation/topics/#{again.id}", %{"outcome" => "reject"})
    end

    assert Repo.get(PendingTopic, again.id)
  end

  @tag req: "MO-04"
  test "MO-04 administrators choose how a category takes new topics", %{
    conn: conn,
    admin: admin,
    general: general
  } do
    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/categories")
    lv |> element("#category-#{general.id} button", "Edit") |> render_click()

    lv
    |> form("#edit-category-#{general.id}", edit: %{new_topics: "new_users"})
    |> render_submit()

    assert Repo.reload!(general).new_topics == "new_users"
    assert has_element?(lv, "#new-topics-#{general.id}", "New users' topics approved")

    assert {:error, changeset} = Forum.update_category(admin, general, %{"new_topics" => "x"})
    assert changeset.errors[:new_topics]
  end
end
