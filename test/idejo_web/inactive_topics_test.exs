# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Inactive topics (steward decision, 2026-11-01): a topic nobody follows is shown faded.
# Not async: one test turns the `inactive_topics` setting off.
defmodule IdejoWeb.InactiveTopicsTest do
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Reading
  alias Idejo.Repo
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()

    {:ok, topic} =
      Forum.create_topic(starter, general, %{"title" => "Picnic", "body" => "Saturday?"})

    %{admin: admin, general: general, starter: starter, topic: topic}
  end

  defp inactive?(topic), do: hd(Reading.put_inactive([topic])).inactive

  @tag req: "TP-13"
  test "TP-13 a topic nobody follows is inactive", %{starter: starter, topic: topic} do
    refute inactive?(topic)

    :ok = Reading.unfollow(starter, topic)
    assert inactive?(topic)

    # Tuples, as the Unread page holds them, keep their extra.
    assert [{%{inactive: true}, 3}] = Reading.put_inactive([{topic, 3}])

    :ok = Reading.follow(user_fixture(), topic)
    refute inactive?(topic)
  end

  @tag req: "TP-13"
  test "TP-13 a topic followed by everyone, or followed only by a deleted account", %{
    admin: admin,
    starter: starter,
    topic: topic
  } do
    {:ok, _} = Accounts.delete_user(starter, valid_user_password())
    assert inactive?(topic)

    {:ok, topic} = Forum.set_autofollow(admin, topic, true)
    refute inactive?(topic)
  end

  @tag req: "TP-13"
  test "TP-13 the category page fades inactive topics, unless the setting is off", %{
    conn: conn,
    admin: admin,
    general: general,
    starter: starter,
    topic: topic
  } do
    :ok = Reading.unfollow(starter, topic)
    page = conn |> get(~p"/c/#{general.slug}") |> html_response(200)
    assert page =~ ~r/id="topic-#{topic.id}"[^>]*is-inactive/s
    assert page =~ "topic-inactive"

    {:ok, _} = Settings.update_settings(admin, %{"inactive_topics" => "false"})
    page = conn |> get(~p"/c/#{general.slug}") |> html_response(200)
    refute page =~ "is-inactive"
  end

  defp age!(topic, days) do
    at = DateTime.add(DateTime.utc_now(), -days, :day)
    topic |> Ecto.Changeset.change(last_activity_at: at) |> Repo.update!()
  end

  @tag req: "TP-13"
  test "TP-13 a topic with no message for the set number of days is inactive, followed or not",
       %{admin: admin, starter: starter, topic: topic} do
    assert Reading.following?(starter, topic)
    refute inactive?(age!(topic, 69))
    assert inactive?(age!(topic, 71))

    {:ok, _} = Settings.update_settings(admin, %{"inactive_after_days" => "100"})
    refute inactive?(topic |> Repo.reload!())

    assert {:error, changeset} = Settings.update_settings(admin, %{"inactive_after_days" => "6"})
    assert changeset.errors[:inactive_after_days]
    assert Settings.get(:inactive_after_days) == 100
  end

  @tag req: "TP-13"
  test "TP-13 an administrator marks a topic inactive until a message is sent there", %{
    admin: admin,
    starter: starter,
    topic: topic
  } do
    assert {:error, :forbidden} = Forum.mark_inactive(starter, topic)

    {:ok, marked} = Forum.mark_inactive(admin, topic)
    assert Reading.following?(starter, marked)
    assert inactive?(marked)
    assert {[%{action: "topic.inactive"}], _} = Idejo.Moderation.list(admin, [])

    {:ok, _} = Forum.post_message(user_fixture(), marked, %{"body" => "Still here"})
    refute inactive?(Repo.reload!(marked))
  end

  @tag req: "TP-13"
  test "TP-13 the topic menu tells administrators how many follow a topic", %{
    conn: conn,
    admin: admin,
    starter: starter,
    topic: topic
  } do
    :ok = Reading.follow(user_fixture(), topic)
    admin_conn = log_in_user(conn, admin)

    assert %{"following" => 2, "inactive" => false, "category_id" => category_id} =
             admin_conn |> get(~p"/topic-menu/#{topic.id}") |> json_response(200)

    assert category_id == topic.category_id

    # Followed by everyone: every active user who did not unfollow it.
    {:ok, topic} = Forum.set_autofollow(admin, topic, true)
    :ok = Reading.unfollow(starter, topic)
    active = Repo.aggregate(from(u in Idejo.Accounts.User, where: u.status == "active"), :count)
    assert Reading.follower_count(topic) == active - 1

    member_conn = log_in_user(build_conn(), user_fixture())
    assert member_conn |> get(~p"/topic-menu/#{topic.id}") |> json_response(404)

    # The menu's administrator items are only in administrators' pages.
    assert admin_conn |> get(~p"/") |> html_response(200) =~ ~s(id="topic-menu-admin")
    refute member_conn |> get(~p"/") |> html_response(200) =~ ~s(id="topic-menu-admin")
  end

  @tag req: "TP-13"
  test "TP-13 the topic menu's actions lead back to the page it was opened on", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic
  } do
    {:ok, other} = Forum.create_category(admin, %{"name" => "Other"})
    conn = log_in_user(conn, admin)
    from_category = put_req_header(conn, "referer", "http://www.example.com/c/#{general.slug}")

    post_menu = fn conn, params ->
      post(conn, ~p"/t/#{topic.id}/moderate", Map.put(params, "return", "back"))
    end

    assert from_category |> post_menu.(%{"action" => "inactive"}) |> redirected_to() ==
             "/c/#{general.slug}"

    assert inactive?(Repo.reload!(topic))

    moved = post_menu.(from_category, %{"action" => "move", "category_id" => other.id})
    assert redirected_to(moved) == "/c/#{general.slug}"
    assert Repo.reload!(topic).category_id == other.id

    # Deleted from its own page: not back to it.
    from_topic =
      put_req_header(conn, "referer", "http://www.example.com/t/#{topic.id}/#{topic.slug}")

    deleted = post_menu.(from_topic, %{"action" => "delete", "confirm" => "yes"})
    assert redirected_to(deleted) == "/c/#{other.slug}"
    refute Repo.get(Idejo.Forum.Topic, topic.id)
  end
end
