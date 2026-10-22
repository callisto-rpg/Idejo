# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ThemeController do
  @moduledoc """
  The server's stylesheet (steward decision, 2026-10-23), written in **Admin → Stylesheet**
  and served at `/theme.css`, after Idejo's own styles. A stylesheet from the app itself, so
  the content security policy allows it (`style-src 'self'`); pages link it with `?v=` and a
  hash of its text (`version/1`), so browsers keep it until it changes.
  """
  use IdejoWeb, :controller

  alias Idejo.Settings

  def show(conn, params) do
    css = Settings.get(:custom_css)

    # A versioned address never changes; the bare one is checked each time.
    cache =
      if params["v"] == version(css),
        do: "public, max-age=31536000, immutable",
        else: "no-cache"

    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", cache)
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, css)
  end

  @doc "A short hash of the stylesheet's text, for its address."
  @spec version(String.t()) :: String.t()
  def version(css),
    do: :crypto.hash(:sha256, css) |> binary_part(0, 8) |> Base.url_encode64(padding: false)
end
