# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AP08SignInTest do
  @moduledoc "AP-07, AP-08, AP-09: discovery, the app's sign-in with PKCE, and device tokens."
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures
  import IdejoWeb.ApiHelpers
  import Phoenix.LiveViewTest

  alias Idejo.Accounts
  alias Idejo.Accounts.ApiTokens
  alias Idejo.Repo

  defp authorize(conn, params), do: get(conn, ~p"/app/authorize?#{params}")

  defp allow(conn, params, choice \\ "allow"),
    do: post(conn, ~p"/app/authorize", Map.put(params, "choice", choice))

  defp code_from(conn) do
    location = redirected_to(conn, 302)
    assert String.starts_with?(location, "org.idejo.app:/oauth/callback?")
    location |> URI.parse() |> Map.get(:query) |> URI.decode_query()
  end

  defp token_request(code, verifier, extra \\ %{}) do
    Map.merge(
      %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => ApiTokens.redirect_uri(),
        "client_id" => ApiTokens.client_id(),
        "code_verifier" => verifier
      },
      extra
    )
  end

  @tag req: "AP-07"
  test "AP-07 discovery tells the app everything before sign-in, with no cookie", %{conn: conn} do
    conn = get(conn, ~p"/.well-known/idejo")
    body = json_response(conn, 200)

    assert body["api"] == %{
             "versions" => ["v1"],
             "base" => "/api/v1",
             "openapi" => "/api/v1/openapi.json",
             "socket" => "/api/v1/socket"
           }

    assert body["oauth"]["client_id"] == "org.idejo.app"
    assert body["oauth"]["scopes"] == ~w(read write private moderate push)
    assert body["idejo_version"] == Idejo.Health.version()
    assert body["community"] == %{"directory_url" => nil}
    assert body["limits"]["page_size"] == 100
    assert get_resp_header(conn, "set-cookie") == []
    check(body, "Discovery")
  end

  @tag req: "AP-08"
  test "AP-08 the whole flow: sign in, confirm, Allow, exchange the code", %{conn: conn} do
    user = user_fixture()
    {verifier, challenge} = pkce()
    params = authorize_params(challenge)

    # Not signed in: the normal sign-in, coming back here.
    visitor = authorize(conn, params)
    assert redirected_to(visitor) == ~p"/users/sign-in"
    assert get_session(visitor, :user_return_to) =~ "/app/authorize?"

    signed_in = log_in_user(conn, user)
    page = authorize(signed_in, params) |> html_response(200)
    assert page =~ "Sign in to the idejo app on this device as"
    assert page =~ user.display_name
    assert page =~ "Test phone"
    assert page =~ "app-authorize-allow"

    query = signed_in |> allow(params) |> code_from()
    assert query["state"] == "xyz"

    conn = post(build_conn(), ~p"/api/v1/oauth/token", token_request(query["code"], verifier))
    body = api_json(conn, 200)
    assert "idj_" <> _ = body["access_token"]
    assert body["token_type"] == "Bearer"
    assert body["scope"] == "read write private moderate push"
    assert body["user"]["id"] == user.id
    refute Map.has_key?(body, "expires_in")
    assert get_resp_header(conn, "set-cookie") == []

    # Only hashes are stored.
    [row] = ApiTokens.list(user)
    assert row.name == "Test phone"
    refute row.token_hash == body["access_token"]
    assert row.token_hash == :crypto.hash(:sha256, body["access_token"])

    me = build_conn() |> api_conn(body["access_token"]) |> get(~p"/api/v1/me") |> api_json(200)
    assert me["email"] == user.email
  end

  @tag req: "AP-08"
  test "AP-08 Cancel goes back to the app with access_denied", %{conn: conn} do
    user = user_fixture()
    {_verifier, challenge} = pkce()

    query =
      conn |> log_in_user(user) |> allow(authorize_params(challenge), "cancel") |> code_from()

    assert query == %{"error" => "access_denied", "state" => "xyz"}
  end

  @tag req: "AP-08"
  test "AP-08 a wrong client, redirect or PKCE gives an error page, never a redirect", %{
    conn: conn
  } do
    conn = log_in_user(conn, user_fixture())
    {_verifier, challenge} = pkce()

    for extra <- [
          %{"client_id" => "com.example.other"},
          %{"redirect_uri" => "https://evil.example.com/cb"},
          %{"redirect_uri" => "org.idejo.app:/oauth/other"},
          %{"code_challenge_method" => "plain"},
          %{"code_challenge_method" => nil},
          %{"code_challenge" => "short"},
          %{"code_challenge" => nil},
          %{"response_type" => "token"},
          %{"scope" => "read admin"}
        ] do
      params = authorize_params(challenge, extra) |> Map.reject(fn {_k, v} -> is_nil(v) end)
      page = authorize(conn, params)
      assert html_response(page, 400) =~ "does not come from the official idejo app"
      assert get_resp_header(page, "location") == []

      refused = allow(conn, params)
      assert html_response(refused, 400)
      assert get_resp_header(refused, "location") == []
    end

    assert Repo.aggregate(Idejo.Accounts.ApiCode, :count) == 0
  end

  @tag req: "AP-08"
  test "AP-08 a wrong verifier, an expired code and a reused one are refused", %{conn: conn} do
    user = user_fixture()
    signed_in = log_in_user(conn, user)

    # Wrong verifier.
    {_verifier, challenge} = pkce()
    query = signed_in |> allow(authorize_params(challenge)) |> code_from()
    {other, _} = pkce()
    conn = post(build_conn(), ~p"/api/v1/oauth/token", token_request(query["code"], other))
    assert api_json(conn, 400)["error"]["code"] == "invalid_grant"

    # Expired code.
    {verifier, challenge} = pkce()
    query = signed_in |> allow(authorize_params(challenge)) |> code_from()

    Repo.update_all(Idejo.Accounts.ApiCode,
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )

    conn = post(build_conn(), ~p"/api/v1/oauth/token", token_request(query["code"], verifier))
    assert api_json(conn, 400)["error"]["code"] == "invalid_grant"

    # Reused code: refused, and the token it gave is revoked (RFC 6749 §4.1.2).
    {verifier, challenge} = pkce()
    query = signed_in |> allow(authorize_params(challenge)) |> code_from()

    first =
      post(build_conn(), ~p"/api/v1/oauth/token", token_request(query["code"], verifier))
      |> api_json(200)

    again = post(build_conn(), ~p"/api/v1/oauth/token", token_request(query["code"], verifier))
    assert api_json(again, 400)["error"]["code"] == "invalid_grant"
    assert {:error, :invalid} = Accounts.get_user_by_api_token(first["access_token"])

    # Another client or redirect at the token endpoint.
    conn =
      post(
        build_conn(),
        ~p"/api/v1/oauth/token",
        token_request("x", verifier, %{"client_id" => "other"})
      )

    assert api_json(conn, 401)["error"]["code"] == "invalid_client"

    conn =
      post(
        build_conn(),
        ~p"/api/v1/oauth/token",
        token_request("x", verifier, %{"grant_type" => "password"})
      )

    assert api_json(conn, 400)["error"]["code"] == "unsupported_grant_type"
  end

  @tag req: "AP-08"
  test "AP-08 Allow without a CSRF token is refused", %{conn: conn} do
    user = user_fixture()
    {_verifier, challenge} = pkce()

    conn =
      conn
      |> log_in_user(user)
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      post(
        conn,
        ~p"/app/authorize",
        Map.merge(authorize_params(challenge), %{"choice" => "allow", "_csrf_token" => "nope"})
      )
    end
  end

  @tag req: "AP-08"
  test "AP-08 a banned member cannot authorize: the session is gone, as on the web", %{conn: conn} do
    user = user_fixture()
    moderator = user_with_role_fixture(:moderator)
    signed_in = log_in_user(conn, user)
    {:ok, _} = Accounts.ban_for(moderator, user, :forever, nil)
    {_verifier, challenge} = pkce()

    assert redirected_to(authorize(signed_in, authorize_params(challenge))) == ~p"/users/sign-in"
    {:ok, request} = ApiTokens.check_request(authorize_params(challenge))
    assert ApiTokens.create_code(Accounts.get_user!(user.id), request) == {:error, :banned}
  end

  @tag req: "AP-08"
  test "AP-08 closed and invite-only registration apply on the way through sign-up", %{conn: conn} do
    {_verifier, challenge} = pkce()
    admin = user_with_role_fixture(:administrator)
    {:ok, _} = Idejo.Settings.update_settings(admin, %{"registration_mode" => "closed"})

    # The app's visitor is sent to sign in; signing up there is closed, as on the web.
    assert redirected_to(authorize(conn, authorize_params(challenge))) == ~p"/users/sign-in"
    assert html_response(get(conn, ~p"/users/sign-up"), 200) =~ "not taking new members"

    {:ok, _} = Idejo.Settings.update_settings(admin, %{"registration_mode" => "invite_only"})
    assert {:error, %Ecto.Changeset{}} = Accounts.register_with_password(valid_user_attributes())
  end

  @tag req: "AP-09"
  test "AP-09 revoke signs the device out; it always answers 204", %{conn: conn} do
    user = user_fixture()
    {token, _row} = api_token_fixture(user)

    assert conn |> api_conn(token) |> post(~p"/api/v1/oauth/revoke") |> api_json(204)
    assert {:error, :invalid} = Accounts.get_user_by_api_token(token)
    assert build_conn() |> api_conn(token) |> get(~p"/api/v1/me") |> api_json(401)

    assert build_conn()
           |> post(~p"/api/v1/oauth/revoke", %{"token" => "idj_unknown"})
           |> api_json(204)
  end

  @tag req: "AP-09"
  test "AP-09 a 21st device revokes the oldest" do
    user = user_fixture()
    [{first, _} | _] = for _ <- 1..21, do: api_token_fixture(user)
    assert length(ApiTokens.list(user)) == 20
    assert {:error, :invalid} = Accounts.get_user_by_api_token(first)
  end

  @tag req: "AP-09"
  test "AP-09 password reset and change, ban and deletion revoke every device" do
    for ending <- [:reset, :change, :ban, :delete] do
      user = user_fixture()
      {token, _row} = api_token_fixture(user)

      case ending do
        :reset ->
          {:ok, _} = Accounts.reset_user_password(user, %{password: "new valid password"})

        :change ->
          {:ok, _} =
            Accounts.update_user_password(
              user,
              %{"current_password" => valid_user_password(), "password" => "new valid password"},
              Accounts.generate_user_session_token(user)
            )

        :ban ->
          {:ok, _} = Accounts.ban_for(user_with_role_fixture(:moderator), user, {:days, 7}, nil)

        :delete ->
          {:ok, _} = Accounts.delete_user(user, valid_user_password())
      end

      assert {:error, :invalid} = Accounts.get_user_by_api_token(token),
             "#{ending} kept the token"
    end
  end

  @tag req: "AP-09"
  test "AP-09 Remove in Profile and account signs the device out, without JavaScript", %{
    conn: conn
  } do
    user = user_fixture()
    {token, row} = api_token_fixture(user)
    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, ~p"/users/settings")
    assert html =~ "Apps and devices"
    assert html =~ "Test phone"
    assert html =~ ~s(action="/users/settings/apps/#{row.id}")

    conn = delete(conn, ~p"/users/settings/apps/#{row.id}")
    assert redirected_to(conn) == "/users/settings?tab=account#apps-section"
    assert {:error, :invalid} = Accounts.get_user_by_api_token(token)

    # Another user's device is not theirs to remove.
    other = user_fixture()
    {other_token, other_row} = api_token_fixture(other)
    delete(log_in_user(build_conn(), user), ~p"/users/settings/apps/#{other_row.id}")
    assert {:ok, _, _} = Accounts.get_user_by_api_token(other_token)
  end

  @tag req: "AP-09"
  test "AP-09 devices are listed and removed through the API too", %{conn: conn} do
    user = user_fixture()
    {token, row} = api_token_fixture(user)
    {_other, other_row} = api_token_fixture(user)

    list = conn |> api_conn(token) |> get(~p"/api/v1/me/tokens") |> api_json(200)
    assert Enum.find(list["data"], &(&1["id"] == row.id))["current"]
    refute Enum.find(list["data"], &(&1["id"] == other_row.id))["current"]

    assert build_conn()
           |> api_conn(token)
           |> delete(~p"/api/v1/me/tokens/#{other_row.id}")
           |> api_json(204)

    assert [%{id: id}] = ApiTokens.list(user)
    assert id == row.id
  end
end
