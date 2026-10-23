# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ManifestController do
  @moduledoc """
  The web app manifest (CL-01), at `/manifest.webmanifest`: the server's name, the Idejo
  icons, and `standalone`, so the site can be installed, which iPhones and iPads need before
  they take push notifications (PN-22). No session, nothing personal.
  """
  use IdejoWeb, :controller

  def show(conn, _params) do
    name = IdejoWeb.Layouts.server_name()

    manifest = %{
      name: name,
      short_name: name,
      start_url: "/",
      scope: "/",
      display: "standalone",
      icons: [
        %{src: ~p"/images/icon-192.png", sizes: "192x192", type: "image/png"},
        %{src: ~p"/images/icon-512.png", sizes: "512x512", type: "image/png"}
      ]
    }

    conn
    |> put_resp_content_type("application/manifest+json")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, Jason.encode!(manifest))
  end
end
