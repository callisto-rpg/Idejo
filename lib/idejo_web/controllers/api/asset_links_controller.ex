# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AssetLinksController do
  @moduledoc """
  `GET /.well-known/assetlinks.json` (IX-03): Android's Digital Asset Links, so the official
  app (`org.idejo.app`) is verified to open this forum's links (its DL-01). Names the
  fingerprints of the app's release keys, plus those in IDEJO_ANDROID_FINGERPRINTS for apps
  built and signed by others. No session, no cookie. With no fingerprint at all, 404: links
  open in the browser.
  """
  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  @package "org.idejo.app"

  def show(conn, _params) do
    case fingerprints() do
      [] ->
        send_resp(conn, 404, "")

      prints ->
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> json([
          %{
            relation: ["delegate_permission/common.handle_all_urls"],
            target: %{
              namespace: "android_app",
              package_name: @package,
              sha256_cert_fingerprints: prints
            }
          }
        ])
    end
  end

  @doc "The release keys' SHA-256 fingerprints, then the configured ones, each once."
  def fingerprints do
    (Application.get_env(:idejo, :android_fingerprints, []) ++
       Application.get_env(:idejo, :extra_android_fingerprints, []))
    |> Enum.uniq()
  end
end
