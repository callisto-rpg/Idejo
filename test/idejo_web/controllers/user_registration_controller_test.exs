# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserRegistrationControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Swoosh.TestAssertions
  import Idejo.AccountsFixtures

  alias Idejo.Accounts

  describe "GET /users/sign-up" do
    @tag req: "AC-01"
    test "AC-01 renders the sign-up form", %{conn: conn} do
      conn = get(conn, ~p"/users/sign-up")
      response = html_response(conn, 200)
      assert response =~ "Create an account"
      assert response =~ ~s(name="user[email]")
      assert response =~ ~s(name="user[username]")
      assert response =~ ~s(name="user[display_name]")
      assert response =~ ~s(name="user[password]")
    end

    @tag req: "AC-01"
    test "AC-01 redirects if already signed in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/sign-up")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/sign-up" do
    @tag req: "AC-01"
    test "AC-01 creates an unverified account, signs in and emails a verification link", %{
      conn: conn
    } do
      email = unique_user_email()
      conn = post(conn, ~p"/users/sign-up", %{"user" => valid_user_attributes(email: email)})

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "open it to verify"

      user = Accounts.get_user_by_email_and_password(email, valid_user_password())
      refute Accounts.confirmed?(user)
      assert_email_sent(to: email, subject: "Verify your email address")

      # The verification notice is shown until the address is verified.
      conn = get(recycle(conn), ~p"/")
      assert html_response(conn, 200) =~ "Please verify your email address"
    end

    @tag req: "AC-01"
    test "AC-01 renders errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/sign-up", %{
          "user" => %{"email" => "with spaces", "username" => "x", "password" => "short"}
        })

      response = html_response(conn, 200)
      assert response =~ "must have the @ sign and no spaces"
      assert response =~ "should be at least 3 character"
      assert response =~ "should be at least 12 character"
      refute get_session(conn, :user_token)
    end
  end
end
