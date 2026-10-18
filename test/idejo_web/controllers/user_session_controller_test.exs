# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSessionControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  setup do
    %{user: user_fixture(), unconfirmed_user: unconfirmed_user_fixture()}
  end

  describe "GET /users/sign-in" do
    @tag req: "AC-01"
    test "AC-01 renders the email and password form", %{conn: conn} do
      conn = get(conn, ~p"/users/sign-in")
      response = html_response(conn, 200)
      assert response =~ "Sign in"
      assert response =~ ~p"/users/sign-up"
      assert response =~ ~s(name="user[password]")
    end
  end

  describe "POST /users/sign-in" do
    @tag req: "AC-01"
    test "AC-01 signs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/sign-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      conn = get(recycle(conn), ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.display_name
      assert response =~ ~p"/users/sign-out"
      refute response =~ "Please verify your email address"
    end

    @tag req: "AC-01"
    test "AC-01 an unverified user can sign in and is asked to verify", %{
      conn: conn,
      unconfirmed_user: user
    } do
      conn =
        post(conn, ~p"/users/sign-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      conn = get(recycle(conn), ~p"/")
      assert html_response(conn, 200) =~ "Please verify your email address"
    end

    @tag req: "AC-01"
    test "AC-01 keeps the user signed in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/sign-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_idejo_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    @tag req: "AC-01"
    test "AC-01 returns to the page that asked for sign-in", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/sign-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/foo/bar"
    end

    @tag req: "AC-01"
    test "AC-01 rejects invalid credentials without saying which is wrong", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, ~p"/users/sign-in", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      assert response =~ "Invalid email or password"
      refute response =~ "invalid_password"
      refute get_session(conn, :user_token)
    end
  end

  describe "DELETE /users/sign-out" do
    @tag req: "AC-01"
    test "AC-01 signs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/sign-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Signed out"
    end

    @tag req: "AC-01"
    test "AC-01 succeeds even if the user is not signed in", %{conn: conn} do
      conn = delete(conn, ~p"/users/sign-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
