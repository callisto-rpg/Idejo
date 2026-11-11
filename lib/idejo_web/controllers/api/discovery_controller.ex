# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.DiscoveryController do
  @moduledoc """
  `GET /.well-known/idejo` (AP-07; steward decision, 2026-11-10): what the app needs to add
  a forum by its address, before anyone signs in. No session, no cookie; rate-limited per
  address like every request (SP-05). While the API is off (AP-20) only the name, the
  address and `"api": null`, so the app can say why.
  """
  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias Idejo.Accounts
  alias Idejo.Accounts.ApiTokens
  alias Idejo.{Api, Community, Gifs, Plugins, Push, Settings}

  def show(conn, _params) do
    base = %{"name" => Settings.get(:server_name), "url" => Api.base() <> "/"}

    body =
      if ApiTokens.enabled?(),
        do: Map.merge(base, details()),
        else: Map.put(base, "api", nil)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(body)
  end

  defp details do
    %{
      "idejo_version" => Idejo.Health.version(),
      "logo_url" => Api.base() <> "/logo",
      "api" => %{
        "versions" => ["v1"],
        "base" => "/api/v1",
        "openapi" => "/api/v1/openapi.json",
        "socket" => "/api/v1/socket"
      },
      "oauth" => %{
        "authorize" => "/app/authorize",
        "token" => "/api/v1/oauth/token",
        "revoke" => "/api/v1/oauth/revoke",
        "client_id" => ApiTokens.client_id(),
        "redirect_uri" => ApiTokens.redirect_uri(),
        "scopes" => ApiTokens.scopes(),
        "code_challenge_methods" => ["S256"]
      },
      "community" => %{"directory_url" => Community.directory_url()},
      "account" => %{
        "deletion_url" => Api.base() <> "/users/settings#delete-heading",
        "sign_up_url" => if(Accounts.sign_ups_open?(), do: Api.base() <> "/users/sign-up")
      },
      "features" => features(),
      "limits" => %{
        "page_size" => 100,
        "requests_per_minute" => elem(Idejo.RateLimit.limit(:api_token), 0),
        "upload_max_mb" => Settings.get(:upload_max_mb),
        "devices_per_user" => ApiTokens.max_live()
      }
    }
  end

  defp features do
    [
      {"unifiedpush", Push.enabled?()},
      {"gifs", Gifs.enabled?()},
      {"plugins", Plugins.active() != %{}},
      {"private_messages", true},
      {"polls", true},
      {"scheduled_messages", true},
      {"community_menu", Community.menu?()}
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end
end
