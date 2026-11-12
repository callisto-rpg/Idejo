# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.OAuthController do
  @moduledoc """
  The official app's token endpoint and sign-out (AP-08, AP-09; RFC 6749 §4.1.3, RFC 7636,
  RFC 7009). Form or JSON bodies, no cookie. The token endpoint is rate-limited to 10 a
  minute per address (`:api_oauth`).

  Changes to this module get an extra careful human review (DV-06).
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Accounts.ApiTokens
  alias IdejoWeb.Api.Errors

  plug :oauth_limit when action == :token

  def token(conn, params) do
    case ApiTokens.exchange(params) do
      {:ok, token, row, user} -> grant(conn, token, row, user)
      {:error, :disabled} -> {:error, :not_found}
      error -> error
    end
  end

  defp grant(conn, token, row, user) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{
      "access_token" => token,
      "token_type" => "Bearer",
      "scope" => Enum.join(row.scopes, " "),
      "token_id" => row.id,
      "user" => Api.me(user)
    })
  end

  # RFC 7009: the token as Bearer or in the body; always 204, known or not.
  def revoke(conn, params) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _ -> params["token"]
      end

    :ok = ApiTokens.revoke_by_token(token)
    no_content(conn)
  end

  defp oauth_limit(conn, _opts) do
    case Idejo.RateLimit.check(:api_oauth, conn.remote_ip) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        Errors.send_error(conn, :rate_limited, %{"retry_after" => 60})
    end
  end
end
