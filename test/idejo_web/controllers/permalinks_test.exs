# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PermalinksTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Hello", "body" => "Hi"})

    [message] = Forum.list_messages(topic)
    %{admin: admin, general: general, topic: topic, message: message}
  end

  defp path(uri), do: URI.parse(uri).path

  @tag req: "TP-06"
  test "TP-06 a message's permalink is its URI and leads to it on the topic page", %{
    conn: conn,
    topic: topic,
    message: message
  } do
    assert path(message.uri) == "/m/#{message.id}"

    conn = get(conn, path(message.uri))
    assert redirected_to(conn, 302) == "/t/#{topic.id}/hello#message-#{message.id}"

    html = conn |> recycle() |> get(~p"/t/#{topic.id}/hello") |> html_response(200)
    assert html =~ ~s(id="message-#{message.id}")
    assert html =~ ~s(href="/m/#{message.id}")
  end

  @tag req: "TP-07"
  test "TP-07 a notification's link leads to the oldest unread message in the topic", %{
    topic: topic,
    message: first
  } do
    reader = user_fixture()
    conn = log_in_user(build_conn(), reader)
    # Opened once: everything up to the first message is read.
    conn |> get(~p"/t/#{topic.id}/hello") |> html_response(200)

    author = user_fixture()
    {:ok, oldest} = Forum.post_message(author, topic, %{"body" => "One"})
    {:ok, latest} = Forum.post_message(author, topic, %{"body" => "Two @#{reader.username}"})

    assert redirected_to(get(conn, ~p"/m/#{latest.id}?unread"), 302) ==
             "/t/#{topic.id}/hello#message-#{oldest.id}"

    # A permalink still names its own message.
    assert redirected_to(get(conn, ~p"/m/#{latest.id}"), 302) ==
             "/t/#{topic.id}/hello#message-#{latest.id}"

    # Read now: the notification leads to its message.
    conn |> get(~p"/t/#{topic.id}/hello") |> html_response(200)

    assert redirected_to(get(conn, ~p"/m/#{latest.id}?unread"), 302) ==
             "/t/#{topic.id}/hello#message-#{latest.id}"

    # Visitors, and a topic never opened, too.
    assert redirected_to(get(build_conn(), ~p"/m/#{first.id}?unread"), 302) ==
             "/t/#{topic.id}/hello#message-#{first.id}"

    stranger = log_in_user(build_conn(), user_fixture())

    assert redirected_to(get(stranger, ~p"/m/#{latest.id}?unread"), 302) ==
             "/t/#{topic.id}/hello#message-#{latest.id}"
  end

  @tag req: "TP-06"
  test "TP-06 a topic's permalink is its URI", %{conn: conn, topic: topic} do
    assert path(topic.uri) == "/t/#{topic.id}"
    assert redirected_to(get(conn, path(topic.uri)), 301) == "/t/#{topic.id}/hello"
  end

  @tag req: "TP-06"
  test "TP-06 permalinks keep working when the topic's title and slug change", %{
    conn: conn,
    topic: topic,
    message: message
  } do
    topic |> Ecto.Changeset.change(title: "Renamed", slug: "renamed") |> Repo.update!()

    assert redirected_to(get(conn, path(topic.uri)), 301) == "/t/#{topic.id}/renamed"
    assert redirected_to(get(conn, "/t/#{topic.id}/hello"), 301) == "/t/#{topic.id}/renamed"

    assert redirected_to(get(conn, path(message.uri)), 302) ==
             "/t/#{topic.id}/renamed#message-#{message.id}"
  end

  @tag req: "TP-06"
  test "TP-06 permalinks keep working when the topic moves to another category", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic,
    message: message
  } do
    {:ok, other} = Forum.create_category(admin, %{"name" => "Other"})
    {:ok, _} = Forum.delete_category(admin, general, topics: {:move, other})

    assert redirected_to(get(conn, path(message.uri)), 302) ==
             "/t/#{topic.id}/hello#message-#{message.id}"

    assert conn |> get(~p"/t/#{topic.id}/hello") |> html_response(200) =~ ~s(href="/c/other")
  end

  @tag req: "TP-06"
  test "TP-06 a message visitors may not view leads to sign-in, or home", %{
    conn: conn,
    admin: admin,
    general: general,
    message: message
  } do
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), general, :view, :deny)

    for path <- [~p"/m/#{message.id}", ~p"/m/#{Ecto.UUID.generate()}", ~p"/m/nope"] do
      res = get(conn, path)
      assert redirected_to(res) == ~p"/users/sign-in"
      assert get_session(res, :user_return_to) == path
    end

    signed_in = build_conn() |> log_in_user(user_fixture())
    assert redirected_to(get(signed_in, ~p"/m/#{Ecto.UUID.generate()}")) == ~p"/"

    member = build_conn() |> log_in_user(user_fixture())
    assert redirected_to(get(member, ~p"/m/#{message.id}"), 302) =~ "#message-#{message.id}"
  end
end
