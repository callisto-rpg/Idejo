# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserPasswordChangeTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias IdejoWeb.UserAuth

  @new_password "a brand new password"

  setup %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, token: get_session(conn, :user_token)}
  end

  defp change(lv, attrs) do
    lv |> form("#password-form", password: attrs) |> render_submit()
  end

  @tag req: "AC-01"
  test "AC-01 a user changes their password from the profile", %{
    conn: conn,
    user: user,
    token: token
  } do
    # Another browser, signed in as the same user.
    other = log_in_user(build_conn(), user)
    other_token = get_session(other, :user_token)
    IdejoWeb.Endpoint.subscribe(UserAuth.live_socket_id(Accounts.session_socket_id(other_token)))

    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    html =
      change(lv, %{
        current_password: valid_user_password(),
        password: @new_password,
        password_confirmation: @new_password
      })

    assert html =~ "Password changed. You were signed out everywhere else."
    assert Accounts.get_user_by_email_and_password(user.email, @new_password)
    refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())

    # This session stays signed in; the other one ends and its LiveViews disconnect.
    assert Accounts.get_user_by_session_token(token)
    refute Accounts.get_user_by_session_token(other_token)
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    assert {:ok, _lv, _html} = live(conn, ~p"/users/settings")
  end

  @tag req: "AC-01"
  test "AC-01 the current password is required", %{conn: conn, user: user, token: token} do
    other_token = Accounts.generate_user_session_token(user)
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    html =
      change(lv, %{
        current_password: "not my password",
        password: @new_password,
        password_confirmation: @new_password
      })

    assert html =~ "is not your current password"
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    assert Accounts.get_user_by_session_token(token)
    assert Accounts.get_user_by_session_token(other_token)
  end

  @tag req: "AC-01"
  test "AC-01 the new password follows the same rules as at sign-up", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    html =
      change(lv, %{
        current_password: valid_user_password(),
        password: "short",
        password_confirmation: "other"
      })

    assert html =~ "should be at least 12 character"
    assert html =~ "does not match password"
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
  end

  @tag req: "AC-01"
  test "AC-01 changing the password ends emailed links too", %{user: user, token: token} do
    reset =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(user, url)
      end)

    {:ok, _} =
      Accounts.update_user_password(
        user,
        %{
          "current_password" => valid_user_password(),
          "password" => @new_password,
          "password_confirmation" => @new_password
        },
        token
      )

    refute Accounts.get_user_by_reset_password_token(reset)
  end
end
