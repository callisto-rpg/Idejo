# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AC05GuestReadingTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)

    {:ok, general} =
      Forum.create_category(admin, %{"name" => "General", "description" => "Talk about anything"})

    {:ok, team} = Forum.create_category(admin, %{"name" => "Team room"})
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), team, :view, :deny)

    %{admin: admin, general: general, team: team}
  end

  @tag req: "AC-05"
  test "AC-05 visitors see the public categories on the home page", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "General"
    assert html =~ "Talk about anything"
    assert html =~ ~s(href="/c/general")
    refute html =~ "Team room"
  end

  @tag req: "AC-05"
  test "AC-05 visitors read a public category page without JavaScript", %{conn: conn} do
    html = conn |> get(~p"/c/general") |> html_response(200)

    assert html =~ "General"
    assert html =~ "Talk about anything"
    assert html =~ "General · Idejo"
    # Server-rendered: not a LiveView.
    refute html =~ "data-phx-main"
  end

  @tag req: "AC-05"
  test "AC-05 a category visitors may not view is not found", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/c/team-room") end
    assert_error_sent 404, fn -> get(conn, ~p"/c/nowhere") end
  end

  @tag req: "AC-05"
  test "AC-05 members see what their roles allow", %{conn: conn, admin: admin} do
    # Unverified users act as guest.
    html = conn |> log_in_user(unconfirmed_user_fixture()) |> get(~p"/") |> html_response(200)
    refute html =~ "Team room"

    html = build_conn() |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200)
    assert html =~ "Team room"

    html = build_conn() |> log_in_user(admin) |> get(~p"/c/team-room") |> html_response(200)
    assert html =~ "Team room"
  end

  @tag req: "AC-05"
  test "AC-05 the home page says when there is nothing to read", %{conn: conn, admin: admin} do
    for category <- Forum.list_categories(), do: {:ok, _} = Forum.delete_category(admin, category)

    assert conn |> get(~p"/") |> html_response(200) =~ "Nothing to read here yet."
  end
end
