# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sets a strict `content-security-policy` header on browser responses (SP-05).

  Everything is served from the app itself (SP-04), so only `'self'` is allowed, but for the
  GIF provider's hosts while GIFs are on (steward decision, 2026-11-03; `Idejo.Gifs`): its
  API for `connect-src`, its media for `img-src`; and, with the community menu, the other
  communities' logos (`Idejo.Community.logo_source/0`, `img-src` only; steward request,
  2026-11-06).
  Inline `<script>` and `<style>` elements are refused unless they carry the
  per-request nonce stored in `conn.assigns.script_csp_nonce` and
  `conn.assigns.style_csp_nonce` (used by LiveDashboard and the Swoosh mailbox
  preview in development).
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    script_nonce = nonce()
    style_nonce = nonce()

    conn
    |> assign(:script_csp_nonce, script_nonce)
    |> assign(:style_csp_nonce, style_nonce)
    |> put_resp_header("content-security-policy", policy(script_nonce, style_nonce))
  end

  defp policy(script_nonce, style_nonce) do
    gifs = Idejo.Gifs.csp_sources()
    logos = List.wrap(Idejo.Community.logo_source())

    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{script_nonce}'",
        "style-src 'self' 'nonce-#{style_nonce}'",
        Enum.join(["img-src 'self' data: blob:" | gifs.img ++ logos], " "),
        "font-src 'self' data:",
        Enum.join(["connect-src 'self'" | gifs.connect], " "),
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'"
      ],
      "; "
    )
  end

  defp nonce, do: 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
