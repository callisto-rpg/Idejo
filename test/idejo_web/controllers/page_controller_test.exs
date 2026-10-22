# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PageControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Repo

  test "GET / shows the server name", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "<h1"
    assert response =~ "Idejo"
    refute response =~ "Phoenix"
  end

  describe "with categories and topics" do
    setup do
      admin = user_with_role_fixture(:administrator)
      starter = user_fixture(%{display_name: "Sam Starter"})
      {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
      {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
      {:ok, team} = Forum.create_category(admin, %{"name" => "Team room"})
      {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), team, :view, :deny)

      older = topic!(starter, general, "Older news", 90)
      newer = topic!(starter, help, "Fresh question", 5)
      secret = topic!(admin, team, "Team plans", 1)

      %{general: general, help: help, team: team, older: older, newer: newer, secret: secret}
    end

    defp topic!(user, category, title, minutes_ago) do
      {:ok, topic} = Forum.create_topic(user, category, %{"title" => title, "body" => "Hi"})

      topic
      |> Ecto.Changeset.change(
        last_activity_at: DateTime.add(DateTime.utc_now(), -minutes_ago * 60)
      )
      |> Repo.update!()
    end

    test "the categories show their topic count and last activity", %{
      conn: conn,
      general: general
    } do
      doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
      card = LazyHTML.query(doc, "#category-#{general.id}")

      assert LazyHTML.text(card) =~ "1 topic"
      assert LazyHTML.text(card) =~ "1 hour ago"
      assert card |> LazyHTML.query("time") |> LazyHTML.attribute("datetime") != []
    end

    test "active topics are listed below, the most recently active first", %{conn: conn} do
      titles =
        conn
        |> get(~p"/")
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#active-topics li > a")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert titles == ["Fresh question", "Older news"]
    end

    test "the sidebar lists the categories, the most recently active first", %{conn: conn} do
      names =
        conn
        |> get(~p"/c/general")
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#sidebar li a .sidebar-name")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert names == ["Help", "General"]
    end

    @tag req: "AC-05"
    test "AC-05 the grid, active topics and sidebar show only what the visitor may view", %{
      conn: conn,
      team: team,
      secret: secret
    } do
      html = conn |> get(~p"/") |> html_response(200)
      refute html =~ "Team room"
      refute html =~ "Team plans"
      refute html =~ team.id
      refute html =~ secret.id

      html = build_conn() |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200)
      assert html =~ "Team room"
      assert html =~ "Team plans"
    end

    test "archived topics are not active", %{older: older} do
      older |> Ecto.Changeset.change(state: "archived") |> Repo.update!()
      refute older.id in Enum.map(Forum.list_active_topics(nil), & &1.id)
    end
  end
end
