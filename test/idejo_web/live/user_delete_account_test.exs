# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserDeleteAccountTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias IdejoWeb.UserAuth

  defp delete_account(lv, password) do
    lv |> form("#delete-account-form", delete: %{password: password}) |> render_submit()
  end

  @tag req: "AC-07"
  test "AC-07 a user deletes their own account from the profile", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    other = log_in_user(build_conn(), user) |> get_session(:user_token)
    IdejoWeb.Endpoint.subscribe(UserAuth.live_socket_id(Accounts.session_socket_id(other)))

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    assert {:error, {:redirect, %{to: "/"}}} = delete_account(lv, valid_user_password())

    assert Accounts.get_user(user.id).status == "deleted"
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    # Signed out: the profile now asks to sign in.
    assert {:error, {:redirect, %{to: "/users/sign-in"}}} = live(conn, ~p"/users/settings")
  end

  @tag req: "AC-07"
  test "AC-07 a wrong password deletes nothing", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/users/settings")

    assert delete_account(lv, "not my password") =~ "That is not your current password."
    assert Accounts.get_user(user.id).status == "active"
  end

  @tag req: "AC-07"
  test "AC-07 the last owner is told to make someone else owner first", %{conn: conn} do
    owner = user_with_role_fixture(:owner)
    {:ok, lv, _html} = live(log_in_user(conn, owner), ~p"/users/settings")

    assert delete_account(lv, valid_user_password()) =~ "You are the only owner of this server."
    assert Accounts.get_user(owner.id).status == "active"
  end
end
