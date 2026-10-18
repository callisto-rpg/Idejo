# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserConfirmationControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Swoosh.TestAssertions
  import Idejo.AccountsFixtures

  alias Idejo.Accounts

  setup do
    user = unconfirmed_user_fixture()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_confirmation_instructions(user, url)
      end)

    # Drain the email sent above so later assertions see only new ones.
    assert_email_sent(to: user.email)

    %{user: user, token: token}
  end

  describe "GET /users/confirm/:token" do
    @tag req: "AC-01"
    test "AC-01 shows a verify button without verifying yet", %{
      conn: conn,
      user: user,
      token: token
    } do
      conn = get(conn, ~p"/users/confirm/#{token}")
      response = html_response(conn, 200)
      assert response =~ "Verify my email address"
      assert response =~ ~s(action="/users/confirm/#{token}")
      refute Accounts.confirmed?(Idejo.Repo.reload!(user))
    end
  end

  describe "POST /users/confirm/:token" do
    @tag req: "AC-01"
    test "AC-01 verifies the email address", %{conn: conn, user: user, token: token} do
      conn = post(conn, ~p"/users/confirm/#{token}")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "verified"
      assert Accounts.confirmed?(Idejo.Repo.reload!(user))
    end

    @tag req: "AC-01"
    test "AC-01 rejects an invalid or used link", %{conn: conn, user: user, token: token} do
      conn = post(conn, ~p"/users/confirm/oops")
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
      refute Accounts.confirmed?(Idejo.Repo.reload!(user))

      post(build_conn(), ~p"/users/confirm/#{token}")
      conn = post(build_conn(), ~p"/users/confirm/#{token}")
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end

  describe "POST /users/confirm" do
    @tag req: "AC-01"
    test "AC-01 sends a new link to a signed-in unverified user", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> post(~p"/users/confirm")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "We sent a new link"
      assert_email_sent(to: user.email, subject: "Verify your email address")
    end

    @tag req: "AC-01"
    test "AC-01 sends nothing to a verified user", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> post(~p"/users/confirm")
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "already verified"
    end

    @tag req: "AC-01"
    test "AC-01 requires sign-in", %{conn: conn} do
      conn = post(conn, ~p"/users/confirm")
      assert redirected_to(conn) == ~p"/users/sign-in"
    end
  end
end
