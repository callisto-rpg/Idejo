# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The getting-started card (steward request, 2026-11-09): after each sign-in, Help's
# "Sending" and how the sidebar works, over the page; after the welcome card for a new
# member. "Close" until the next sign-in, "Close and hide this in the future" for good.
defmodule IdejoWeb.IntroCardTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias IdejoWeb.Accessibility

  defp sign_in(conn, user) do
    conn =
      post(conn, ~p"/users/sign-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    recycle(conn)
  end

  defp home(conn), do: conn |> get(~p"/") |> html_response(200)

  defp text(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.text()

  test "after signing in, the card shows Help's Sending and the sidebar", %{conn: conn} do
    user = user_fixture()
    conn = sign_in(conn, user)
    # The next page: the sign-in's flash is gone, the card is still due.
    html = conn |> get(~p"/") |> recycle() |> home()

    assert html =~ ~s(id="intro-card")
    assert text(html, "#intro-title") == "Getting started"

    # Help's "Sending", shortened: Enter and Ctrl+Enter only.
    sending = text(html, "#intro-send")
    assert sending =~ "Sending"
    assert sending =~ "Sends what you wrote."
    assert sending =~ "Finishes your current message and starts a new one."
    refute sending =~ "growing message"
    refute sending =~ "Nothing is sent"
    refute sending =~ "longer delay"

    # The Help page keeps them all.
    help = build_conn() |> get(~p"/help") |> html_response(200) |> text("#help-send")
    assert help =~ "growing message"
    assert help =~ "Nothing is sent"
    assert help =~ "longer delay"

    sidebar = text(html, "#intro-sidebar")
    assert sidebar =~ "Topics you write in are followed automatically and appear in the sidebar"
    assert sidebar =~ "To stop following a topic, click the ×."
    refute sidebar =~ "under their category"
    assert sidebar =~ "swipe right to reveal the sidebar"

    assert text(html, "#intro-close") =~ "Close"
    assert text(html, "#intro-hide") =~ "Close and hide this in the future"
    assert Accessibility.audit(html) == []
  end

  test "without signing in again, it does not show", %{conn: conn} do
    user = user_fixture()
    refute conn |> log_in_user(user) |> home() =~ ~s(id="intro-card")
    refute build_conn() |> home() =~ ~s(id="intro-card")
  end

  test "a new member sees it after the welcome card, not with it", %{conn: conn} do
    newcomer = user_fixture(%{welcome: true})
    conn = sign_in(conn, newcomer)

    html = home(conn)
    assert html =~ ~s(id="welcome-card")
    refute html =~ ~s(id="intro-card")

    conn = conn |> post(~p"/welcome", %{}) |> recycle()
    html = home(conn)
    refute html =~ ~s(id="welcome-card")
    assert html =~ ~s(id="intro-card")
  end

  test "Close: gone until the next sign-in", %{conn: conn} do
    user = user_fixture()
    conn = sign_in(conn, user)

    closed =
      conn
      |> put_req_header("referer", "http://www.example.com/help")
      |> post(~p"/intro", %{"choice" => "close", "return" => "back"})

    assert redirected_to(closed) == "/help"
    refute closed |> recycle() |> home() =~ ~s(id="intro-card")
    refute Accounts.get_user!(user.id).intro_hidden

    assert build_conn() |> sign_in(user) |> home() =~ ~s(id="intro-card")
  end

  test "Close and hide this in the future: never again", %{conn: conn} do
    user = user_fixture()
    conn = sign_in(conn, user)

    hidden = post(conn, ~p"/intro", %{"choice" => "hide", "return" => "back"})
    assert redirected_to(hidden) == "/"
    refute hidden |> recycle() |> home() =~ ~s(id="intro-card")

    stored = Accounts.get_user!(user.id)
    assert stored.intro_hidden
    refute stored.intro_pending

    # Signing in again, on any device, keeps it hidden; it is stored with the account.
    refute build_conn() |> sign_in(user) |> home() =~ ~s(id="intro-card")
    assert {:ok, %{intro_pending: false}} = Accounts.intro_on_sign_in(stored)
  end

  test "the buttons need a signed-in member", %{conn: conn} do
    assert conn |> post(~p"/intro", %{"choice" => "hide"}) |> redirected_to() ==
             ~p"/users/sign-in"
  end
end
