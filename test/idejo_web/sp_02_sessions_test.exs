# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SP02SessionsTest do
  @moduledoc """
  SP-02: passwords hashed with Argon2id; sessions in secure, HTTP-only cookies.
  """
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias IdejoWeb.UserAuth

  @session_cookie "_idejo_key"
  @remember_me_cookie "_idejo_web_user_remember_me"

  defp prod_config do
    Config.Reader.read!("config/config.exs", env: :prod, target: :host)
  end

  defp sign_in(conn, user, extra \\ %{}) do
    post(conn, ~p"/users/sign-in", %{
      "user" => Map.merge(%{"email" => user.email, "password" => valid_user_password()}, extra)
    })
  end

  # A signed-only cookie carries its payload in plain base64; an encrypted one does not.
  defp readable_without_key?(set_cookie, token) do
    [_name, value] =
      set_cookie |> String.split(";", parts: 2) |> hd() |> String.split("=", parts: 2)

    value
    |> String.split(".")
    |> Enum.any?(fn part ->
      case Base.url_decode64(part, padding: false) do
        {:ok, decoded} -> :binary.match(decoded, token) != :nomatch
        :error -> false
      end
    end)
  end

  defp set_cookie_header(conn, name) do
    conn
    |> get_resp_header("set-cookie")
    |> Enum.find(&String.starts_with?(&1, name <> "="))
  end

  describe "passwords" do
    @tag req: "SP-02"
    test "SP-02 passwords are hashed with Argon2id and a unique salt" do
      user = unconfirmed_user_fixture()
      other = unconfirmed_user_fixture()

      assert "$argon2id$v=19$" <> _ = user.password_hash
      assert user.password_hash != other.password_hash
      refute user.password_hash =~ valid_user_password()
    end

    @tag req: "SP-02"
    test "SP-02 production pins the Argon2id cost" do
      argon2 = prod_config()[:argon2_elixir]

      assert argon2[:argon2_type] == 2
      assert argon2[:t_cost] >= 3
      assert argon2[:m_cost] >= 16
      assert argon2[:parallelism] >= 1
    end

    @tag req: "SP-02"
    test "SP-02 an unknown email still costs a hash check" do
      # Without a user, valid_password?/2 runs Argon2.no_user_verify/0, so response time
      # does not reveal whether an email is registered.
      refute User.valid_password?(nil, "anything")
    end
  end

  describe "cookies" do
    setup do
      %{user: user_fixture()}
    end

    @tag req: "SP-02"
    test "SP-02 the session cookie is encrypted, Secure, HttpOnly and SameSite=Lax", %{
      conn: conn,
      user: user
    } do
      conn = sign_in(conn, user)
      cookie = set_cookie_header(conn, @session_cookie)

      assert cookie =~ "; secure"
      assert cookie =~ "; HttpOnly"
      assert cookie =~ "; SameSite=Lax"
      refute readable_without_key?(cookie, get_session(conn, :user_token))
    end

    @tag req: "SP-02"
    test "SP-02 the remember-me cookie is encrypted, Secure, HttpOnly and SameSite=Lax", %{
      conn: conn,
      user: user
    } do
      conn = sign_in(conn, user, %{"remember_me" => "true"})
      cookie = set_cookie_header(conn, @remember_me_cookie)

      assert cookie =~ "; secure"
      assert cookie =~ "; HttpOnly"
      assert cookie =~ "; SameSite=Lax"
      assert cookie =~ "; max-age=1209600"
      refute readable_without_key?(cookie, get_session(conn, :user_token))
    end

    @tag req: "SP-02"
    test "SP-02 production sets the Secure flag on cookies" do
      assert prod_config()[:idejo][:secure_cookies] == true
    end
  end

  describe "session lifecycle" do
    setup do
      %{user: user_fixture()}
    end

    @tag req: "SP-02"
    test "SP-02 signing in renews the session against fixation", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(%{"planted" => "by someone else"})
        |> sign_in(user)

      assert conn.private[:plug_session_info] == :renew
      refute get_session(conn, "planted")
    end

    @tag req: "SP-02"
    test "SP-02 the session token is stored server-side and revoked at sign-out", %{
      conn: conn,
      user: user
    } do
      conn = sign_in(conn, user, %{"remember_me" => "true"})
      token = get_session(conn, :user_token)
      remember_me = conn.resp_cookies[@remember_me_cookie].value
      assert Accounts.get_user_by_session_token(token)

      conn |> recycle() |> delete(~p"/users/sign-out")
      refute Accounts.get_user_by_session_token(token)

      # A copy of the old cookie no longer signs anyone in.
      conn = build_conn() |> put_req_cookie(@remember_me_cookie, remember_me) |> get(~p"/")
      refute conn.assigns.current_scope
    end

    @tag req: "SP-02"
    test "SP-02 signing out disconnects the session's live sockets", %{conn: conn, user: user} do
      conn = sign_in(conn, user)
      token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == UserAuth.live_socket_id(token)

      IdejoWeb.Endpoint.subscribe(UserAuth.live_socket_id(token))
      conn |> recycle() |> delete(~p"/users/sign-out")

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end
  end
end
