# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Café time", "body" => "Hi"})

    %{admin: admin, general: general, topic: topic}
  end

  @tag req: "TP-01"
  test "TP-01 visitors read a public topic without JavaScript", %{conn: conn, topic: topic} do
    html = conn |> get(~p"/t/#{topic.id}/cafe-time") |> html_response(200)

    assert html =~ "Café time"
    assert html =~ ~s(href="/c/general")
    refute html =~ "data-phx-main"
  end

  @tag req: "TP-01"
  test "TP-01 the URI and other slugs redirect to the topic's address", %{
    conn: conn,
    topic: topic
  } do
    for path <- [~p"/t/#{topic.id}", ~p"/t/#{topic.id}/old-title"] do
      conn = get(conn, path)
      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/t/#{topic.id}/cafe-time"
    end
  end

  @tag req: "TP-01"
  test "TP-01 a topic visitors may not view leads to sign-in, and back after it", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic
  } do
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), general, :view, :deny)

    # Hidden, missing or malformed: the same answer, so nothing is given away (AC-05).
    for path <- [
          ~p"/t/#{topic.id}/cafe-time",
          ~p"/t/#{topic.id}",
          ~p"/t/#{Ecto.UUID.generate()}",
          ~p"/t/nope"
        ] do
      res = get(conn, path)
      assert redirected_to(res) == ~p"/users/sign-in"
      assert get_session(res, :user_return_to) == path
    end

    member = user_fixture()
    res = get(conn, ~p"/t/#{topic.id}/cafe-time")

    res =
      res
      |> recycle()
      |> post(~p"/users/sign-in", %{
        "user" => %{"email" => member.email, "password" => valid_user_password()}
      })

    assert redirected_to(res) == ~p"/t/#{topic.id}/cafe-time"
  end

  @tag req: "TP-01"
  test "TP-01 a topic a signed-in user may not view leads home, with a dialog", %{
    admin: admin,
    general: general,
    topic: topic
  } do
    member = user_fixture()

    {:ok, _} =
      Access.set_permission(admin, Access.built_in_role!(:member), general, :view, :deny)

    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), general, :view, :deny)

    conn = build_conn() |> log_in_user(member)

    for path <- [~p"/t/#{topic.id}/cafe-time", ~p"/t/#{Ecto.UUID.generate()}"] do
      res = get(conn, path)
      assert redirected_to(res) == ~p"/"

      page = res |> recycle() |> get(~p"/") |> html_response(200)
      assert page =~ ~s(id="topic-unavailable")

      assert page =~
               "The topic doesn&#39;t exist, was deleted, or you do not have permission to view it."
    end

    # Once only.
    refute conn |> get(~p"/") |> html_response(200) =~ ~s(id="topic-unavailable")
  end
end
