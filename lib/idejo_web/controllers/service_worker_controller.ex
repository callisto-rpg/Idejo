# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ServiceWorkerController do
  @moduledoc """
  The service worker (PN-17) at `/sw.js`, from the site's root so its scope is the whole
  site, and the server's VAPID public key at `/push/key`, which the worker fetches when its
  push subscription must be renewed. No session, nothing personal.

  The worker is `priv/push/sw.js`, embedded here when this module compiles: it imports
  nothing, so it needs no bundling, and it is the same in tests, development and releases.
  Browsers check it for changes on each visit (`no-cache`).
  """
  use IdejoWeb, :controller

  alias Idejo.Push.Vapid

  @path Path.expand("../../../priv/push/sw.js", __DIR__)
  @external_resource @path
  @worker File.read!(@path)

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/javascript")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("service-worker-allowed", "/")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, @worker)
  end

  def key(conn, _params) do
    case Vapid.public_key() do
      nil ->
        send_resp(conn, 404, "")

      key ->
        conn
        |> put_resp_content_type("text/plain")
        |> put_resp_header("cache-control", "no-cache")
        |> send_resp(200, key)
    end
  end
end
