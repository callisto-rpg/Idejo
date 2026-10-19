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
  test "TP-01 a topic visitors may not view is not found", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic
  } do
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), general, :view, :deny)

    assert_error_sent 404, fn -> get(conn, ~p"/t/#{topic.id}/cafe-time") end
    assert_error_sent 404, fn -> get(conn, ~p"/t/#{topic.id}") end
    assert_error_sent 404, fn -> get(conn, ~p"/t/#{Ecto.UUID.generate()}") end
    assert_error_sent 404, fn -> get(conn, ~p"/t/nope") end
  end
end
