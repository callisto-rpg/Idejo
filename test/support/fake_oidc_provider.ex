# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.FakeOIDCProvider do
  @moduledoc """
  An OpenID Connect provider for tests (AC-09), served by Bandit on a free local port:
  discovery (`/.well-known/openid-configuration`), its keys (`/jwks`) and the token
  endpoint, which checks the client's secret and the PKCE verifier and answers with an ID
  token signed by a test key. There is no login page: a test reads the authorization request
  from the app's redirect (`authorization/1`) and makes the code the provider would have
  sent back (`code/3`), with the claims it wants, or broken on purpose.

  `start!/0` sets `config :idejo, :oidc` for the calling test (which must not be async) and
  starts `Idejo.Accounts.OIDC`'s provider worker on it, allowing plain http as only tests do.
  """
  @behaviour Plug

  alias Idejo.Accounts.OIDC

  @client_id "idejo-test"
  @client_secret "test-client-secret"

  @doc "Starts the provider and points the app at it. Returns it, for `code/3`."
  def start!(opts \\ []) do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {:ok, codes} = Agent.start_link(fn -> %{} end)
    state = %{key: key, codes: codes, issuer: nil}

    {:ok, server} =
      Bandit.start_link(
        plug: {__MODULE__, state},
        ip: :loopback,
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    issuer = "http://127.0.0.1:#{port}"
    :ok = Agent.update(codes, &Map.put(&1, :issuer, issuer))

    previous = {Application.get_env(:idejo, :oidc), Application.get_env(:idejo, :local_accounts)}

    Application.put_env(:idejo, :oidc,
      issuer: issuer,
      client_id: @client_id,
      client_secret: @client_secret,
      label: Keyword.get(opts, :label, "Test ID")
    )

    ExUnit.Callbacks.on_exit(fn ->
      {oidc, local} = previous

      if oidc,
        do: Application.put_env(:idejo, :oidc, oidc),
        else: Application.delete_env(:idejo, :oidc)

      Application.put_env(:idejo, :local_accounts, if(local == nil, do: true, else: local))
    end)

    ExUnit.Callbacks.start_supervised!(
      {Oidcc.ProviderConfiguration.Worker,
       %{
         issuer: issuer,
         name: OIDC.provider(),
         provider_configuration_opts: %{quirks: %{allow_unsafe_http: true}}
       }}
    )

    %{issuer: issuer, key: key, codes: codes}
  end

  @doc "The test client's id and secret."
  def client_id, do: @client_id
  def client_secret, do: @client_secret

  @doc "The query of an authorization request the app redirected to, as a map."
  def authorization(location) do
    %URI{query: query} = URI.parse(location)
    URI.decode_query(query)
  end

  @doc """
  A code for the authorization request `request` (from `authorization/1`), whose ID token
  carries the standard claims (the request's nonce, this client as audience, valid for five
  minutes) with `claims` over them. `opts`: `key: :other` signs with a key not in the JWKS.
  """
  def code(provider, request, claims, opts \\ []) do
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{
          "iss" => provider.issuer,
          "aud" => @client_id,
          "iat" => now,
          "exp" => now + 300,
          "nonce" => request["nonce"]
        },
        claims
      )

    code = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    Agent.update(
      provider.codes,
      &Map.put(&1, code, %{
        claims: claims,
        challenge: request["code_challenge"],
        redirect_uri: request["redirect_uri"],
        key: Keyword.get(opts, :key, :right)
      })
    )

    code
  end

  @impl Plug
  def init(state), do: state

  @impl Plug
  def call(%{request_path: "/.well-known/openid-configuration"} = conn, state) do
    issuer = Agent.get(state.codes, & &1.issuer)

    json(conn, 200, %{
      "issuer" => issuer,
      "authorization_endpoint" => issuer <> "/authorize",
      "token_endpoint" => issuer <> "/token",
      "jwks_uri" => issuer <> "/jwks",
      "response_types_supported" => ["code"],
      "subject_types_supported" => ["public"],
      "id_token_signing_alg_values_supported" => ["RS256"],
      "code_challenge_methods_supported" => ["S256"],
      "token_endpoint_auth_methods_supported" => ["client_secret_basic", "client_secret_post"],
      "grant_types_supported" => ["authorization_code"],
      "scopes_supported" => ["openid", "email", "profile"]
    })
  end

  def call(%{request_path: "/jwks"} = conn, state) do
    {_, public} = state.key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    json(conn, 200, %{
      "keys" => [Map.merge(public, %{"kid" => "test", "use" => "sig", "alg" => "RS256"})]
    })
  end

  def call(%{request_path: "/token", method: "POST"} = conn, state) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    params = URI.decode_query(body)
    entry = Agent.get_and_update(state.codes, &Map.pop(&1, params["code"]))

    cond do
      not client?(conn, params) ->
        json(conn, 401, %{"error" => "invalid_client"})

      entry == nil or params["redirect_uri"] != entry.redirect_uri or
          not pkce?(params["code_verifier"], entry.challenge) ->
        json(conn, 400, %{"error" => "invalid_grant"})

      true ->
        key = if entry.key == :right, do: state.key, else: JOSE.JWK.generate_key({:rsa, 2048})

        {_, id_token} =
          key
          |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "test"}, entry.claims)
          |> JOSE.JWS.compact()

        json(conn, 200, %{
          "access_token" => "access-" <> params["code"],
          "token_type" => "Bearer",
          "expires_in" => 300,
          "id_token" => id_token
        })
    end
  end

  def call(conn, _state), do: Plug.Conn.send_resp(conn, 404, "")

  defp client?(conn, params) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Basic " <> encoded] ->
        Base.decode64!(encoded) ==
          URI.encode_www_form(@client_id) <> ":" <> URI.encode_www_form(@client_secret)

      [] ->
        params["client_id"] == @client_id and params["client_secret"] == @client_secret
    end
  end

  defp pkce?(verifier, challenge) when is_binary(verifier) and is_binary(challenge),
    do: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false) == challenge

  defp pkce?(_verifier, _challenge), do: false

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
