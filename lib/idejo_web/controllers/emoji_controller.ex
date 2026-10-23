# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.EmojiController do
  @moduledoc """
  The + reaction picker's list of emoji (TP-17), `Idejo.Emoji.index_json/0`, at
  `/emoji-index.json`. The `EmojiPicker` hook fetches it once per page and draws and searches
  the picker itself, so opening it sends nothing over the live connection. No session; with
  `?v=` and the list's hash, browsers keep it until it changes.
  """
  use IdejoWeb, :controller

  alias Idejo.Emoji

  def index(conn, params) do
    cache =
      if params["v"] == Emoji.index_version(),
        do: "public, max-age=31536000, immutable",
        else: "no-cache"

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", cache)
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, Emoji.index_json())
  end
end
