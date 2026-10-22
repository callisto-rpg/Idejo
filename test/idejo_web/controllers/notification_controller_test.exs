# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NotificationControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Notifications

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    bo = user_fixture(%{username: unique_username("bo")})
    ada = user_fixture(%{display_name: "Ada"})
    {:ok, topic} = Forum.create_topic(bo, general, %{"title" => "Plans", "body" => "Tonight?"})
    %{conn: log_in_user(conn, bo), bo: bo, ada: ada, topic: topic}
  end

  defp ids(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#notifications > li")
    |> LazyHTML.attribute("id")
  end

  @tag req: "NO-01"
  test "NO-01 the Notifications screen lists mentions and replies, unread first", %{
    conn: conn,
    bo: bo,
    ada: ada,
    topic: topic
  } do
    assert conn |> get(~p"/notifications") |> html_response(200) =~ "No notifications yet."

    {:ok, first} = Forum.post_message(ada, topic, %{"body" => "Hi @#{bo.username}"})
    {:ok, second} = Forum.post_message(ada, topic, %{"body" => "Me too"})
    {[newest, oldest], false} = Notifications.list(bo)
    assert newest.message_id == second.id
    assert oldest.message_id == first.id

    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ ~s(id="notifications-link")

    assert home
           |> LazyHTML.from_document()
           |> LazyHTML.query("#notifications-link .header-badge")
           |> LazyHTML.text() =~ "2"

    page = conn |> get(~p"/notifications") |> html_response(200)
    assert page =~ "Ada mentioned you in “Plans”"
    assert page =~ "Ada posted in “Plans”"

    # Opening one marks it read and goes to the message; it moves below the unread one.
    conn = get(conn, ~p"/notifications/#{newest.id}")
    assert redirected_to(conn) == ~p"/m/#{second.id}"
    page = conn |> recycle() |> get(~p"/notifications") |> html_response(200)
    assert ids(page) == ["notification-#{oldest.id}", "notification-#{newest.id}"]

    conn = conn |> recycle() |> post(~p"/notifications/read")
    assert redirected_to(conn) == ~p"/notifications"
    assert Notifications.unread_count(bo) == 0
    refute conn |> recycle() |> get(~p"/notifications") |> html_response(200) =~ "read-all-form"
  end

  @tag req: "NO-01"
  test "NO-01 notifications are only for their owner, signed in", %{
    bo: bo,
    ada: ada,
    topic: topic
  } do
    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "Hi"})
    {[notification], false} = Notifications.list(bo)

    other = log_in_user(build_conn(), user_fixture())
    assert_error_sent 404, fn -> get(other, ~p"/notifications/#{notification.id}") end
    assert redirected_to(get(build_conn(), ~p"/notifications")) == ~p"/users/sign-in"
  end
end
