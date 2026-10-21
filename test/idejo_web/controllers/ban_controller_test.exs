# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.BanControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Accounts

  setup do
    %{
      moderator: user_with_role_fixture(:moderator),
      user: user_fixture(%{display_name: "Spammer"})
    }
  end

  @tag req: "MO-02"
  test "MO-02 a server moderator bans from the user's card; the user is signed out", %{
    moderator: moderator,
    user: user
  } do
    user_conn = log_in_user(build_conn(), user)
    assert user_conn |> get(~p"/users/settings") |> html_response(200)

    mod_conn = log_in_user(build_conn(), moderator)
    page = mod_conn |> get(~p"/u/#{user.id}") |> html_response(200)
    assert page =~ ~s(id="ban-form")
    refute build_conn() |> get(~p"/u/#{user.id}") |> html_response(200) =~ "ban-form"

    refute log_in_user(build_conn(), user_fixture())
           |> get(~p"/u/#{user.id}")
           |> html_response(200) =~ "ban-form"

    conn = post(mod_conn, ~p"/u/#{user.id}/ban", %{"days" => "7", "reason" => "Spam"})
    assert redirected_to(conn) == ~p"/u/#{user.id}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Account banned."
    assert mod_conn |> get(~p"/u/#{user.id}") |> html_response(200) =~ ~s(id="banned-state")

    # The banned user's session no longer counts.
    assert redirected_to(get(user_conn, ~p"/users/settings")) == ~p"/users/sign-in"

    log = mod_conn |> get(~p"/moderation/log") |> html_response(200)
    assert log =~ "Banned an account"
    assert log =~ "Spam"

    conn = delete(mod_conn, ~p"/u/#{user.id}/ban", %{"reason" => "Sorry"})
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Ban lifted."
    refute Accounts.banned?(Accounts.get_user!(user.id))

    # Anything but an offered duration bans nobody.
    post(mod_conn, ~p"/u/#{user.id}/ban", %{"days" => "9999"})
    refute Accounts.banned?(Accounts.get_user!(user.id))
  end

  @tag req: "MO-02"
  test "MO-02 a banned account is told so at sign-in, only with the right password", %{
    moderator: moderator,
    user: user
  } do
    {:ok, _} = Accounts.ban_user(moderator, user, nil)

    conn =
      post(build_conn(), ~p"/users/sign-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert html_response(conn, 200) =~ "This account is banned."
    refute get_session(conn, :user_token)

    conn =
      post(build_conn(), ~p"/users/sign-in", %{
        "user" => %{"email" => user.email, "password" => "wrong password!"}
      })

    assert html_response(conn, 200) =~ "Invalid email or password"
  end
end
