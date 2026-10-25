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
  test "AC-05 a category visitors may not view leads to sign-in, never naming it", %{
    conn: conn
  } do
    # Hidden or missing: the same answer (steward decision, 2026-10-24).
    for path <- [~p"/c/team-room", ~p"/c/nowhere"] do
      res = get(conn, path)
      assert redirected_to(res) == ~p"/users/sign-in"
      assert get_session(res, :user_return_to) == path
    end
  end

  @tag req: "AC-05"
  test "AC-05 a category a signed-in user may not view leads home, with a dialog" do
    # Unverified users act as guest, who may not view the Team room.
    conn = build_conn() |> log_in_user(unconfirmed_user_fixture())

    for path <- [~p"/c/team-room", ~p"/c/nowhere"] do
      res = get(conn, path)
      assert redirected_to(res) == ~p"/"

      page = res |> recycle() |> get(~p"/") |> html_response(200)
      assert page =~ ~s(id="topic-unavailable")

      assert page =~
               "The category doesn&#39;t exist, was deleted, or you do not have permission to view it."

      refute page =~ "Team room"
    end
  end

  @tag req: "AC-05"
  test "AC-05 visitors are offered to sign in until they continue without it", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(id="guest-notice")
    assert html =~ "You are not signed in."
    assert html =~ "You will not be able to post and won&#39;t see any hidden categories."
    assert html =~ ~s(src="/images/logo.svg" alt="Idejo" class="full-logo")
    assert html =~ ~s(action="/continue-as-guest")
    assert html =~ ~s(href="/users/sign-in")
    assert html =~ ~s(href="/users/sign-up")
    refute html =~ "Log in"
    # The home page only.
    refute conn |> get(~p"/c/general") |> html_response(200) =~ ~s(id="guest-notice")

    res = post(conn, ~p"/continue-as-guest")
    assert redirected_to(res) == ~p"/"
    refute res |> recycle() |> get(~p"/") |> html_response(200) =~ ~s(id="guest-notice")

    refute build_conn()
           |> log_in_user(user_fixture())
           |> get(~p"/")
           |> html_response(200) =~ ~s(id="guest-notice")
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
