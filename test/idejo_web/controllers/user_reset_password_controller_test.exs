# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserResetPasswordControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Swoosh.TestAssertions
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias IdejoWeb.UserAuth

  @new_password "a brand new passphrase"

  setup do
    user = user_fixture()
    assert_email_sent(subject: "Verify your email address")
    %{user: user}
  end

  defp reset_token(user) do
    extract_user_token(fn url -> Accounts.deliver_user_reset_password_instructions(user, url) end)
  end

  @tag req: "AC-02"
  test "AC-02 sign-in links to the reset page, which asks for the email", %{conn: conn} do
    assert conn |> get(~p"/users/sign-in") |> html_response(200) =~ ~p"/users/reset-password"

    html = conn |> get(~p"/users/reset-password") |> html_response(200)
    assert html =~ "Reset your password"
    assert html =~ ~s(name="user[email]")
  end

  @tag req: "AC-02"
  test "AC-02 asking for a link emails it", %{conn: conn, user: user} do
    conn = post(conn, ~p"/users/reset-password", %{"user" => %{"email" => user.email}})

    assert redirected_to(conn) == ~p"/users/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If that email has an account"
    assert_email_sent(to: user.email, subject: "Reset your password")
  end

  @tag req: "AC-02"
  test "AC-02 the answer does not tell whether an email has an account", %{conn: conn, user: user} do
    known = post(conn, ~p"/users/reset-password", %{"user" => %{"email" => user.email}})

    unknown =
      post(conn, ~p"/users/reset-password", %{"user" => %{"email" => "nobody@example.org"}})

    assert Phoenix.Flash.get(known.assigns.flash, :info) ==
             Phoenix.Flash.get(unknown.assigns.flash, :info)

    assert redirected_to(known) == redirected_to(unknown)
  end

  @tag req: "AC-02"
  test "AC-02 the link opens a new-password form", %{conn: conn, user: user} do
    token = reset_token(user)
    html = conn |> get(~p"/users/reset-password/#{token}") |> html_response(200)

    assert html =~ "Choose a new password"
    assert html =~ ~s(name="user[password_confirmation]")
    assert html =~ ~s(action="/users/reset-password/#{token}")
  end

  @tag req: "AC-02"
  test "AC-02 a bad link sends back to the request page", %{conn: conn} do
    conn = get(conn, ~p"/users/reset-password/oops")
    assert redirected_to(conn) == ~p"/users/reset-password"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"

    conn = put(build_conn(), ~p"/users/reset-password/oops", %{"user" => %{"password" => "x"}})
    assert redirected_to(conn) == ~p"/users/reset-password"
  end

  @tag req: "AC-02"
  test "AC-02 a new password is set, every session ends and its LiveViews disconnect", %{
    conn: conn,
    user: user
  } do
    signed_in = log_in_user(build_conn(), user)
    session_token = get_session(signed_in, :user_token)
    socket_id = Accounts.session_socket_id(session_token)
    IdejoWeb.Endpoint.subscribe(UserAuth.live_socket_id(socket_id))

    token = reset_token(user)

    conn =
      put(conn, ~p"/users/reset-password/#{token}", %{
        "user" => %{"password" => @new_password, "password_confirmation" => @new_password}
      })

    assert redirected_to(conn) == ~p"/users/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password changed"
    assert Accounts.get_user_by_email_and_password(user.email, @new_password)

    refute Accounts.get_user_by_session_token(session_token)
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    # The old session cannot open pages as the user anymore.
    refute signed_in |> recycle() |> get(~p"/") |> Map.get(:assigns) |> Map.get(:current_scope)
  end

  @tag req: "AC-02"
  test "AC-02 password errors show on the form", %{conn: conn, user: user} do
    token = reset_token(user)

    html =
      conn
      |> put(~p"/users/reset-password/#{token}", %{
        "user" => %{"password" => "short", "password_confirmation" => "other"}
      })
      |> html_response(200)

    assert html =~ "should be at least 12 character"
    assert html =~ "does not match password"
    refute html =~ "short"
  end
end
