# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Gifs.Provider do
  @moduledoc """
  A GIF provider (steward decision, 2026-11-03): what idejo needs to know about the service
  the `!gif` overlay searches. The browser talks to the provider itself, through the adapter
  of the same `id/0` in `assets/js/gifs/` (`index.js` lists them); the server only says
  which provider, with which key and filter, and lets the browser reach its hosts
  (`IdejoWeb.Plugs.ContentSecurityPolicy`).

  To swap providers: a module with these callbacks, an adapter in `assets/js/gifs/`, and
  `config :idejo, :gif_provider, Module`.
  """

  @doc "The adapter's name in `assets/js/gifs/index.js`."
  @callback id() :: String.t()

  @doc "The provider's name, as shown to people (\"Powered by …\")."
  @callback name() :: String.t()

  @doc "The search box's placeholder (KLIPY requires \"Search KLIPY\")."
  @callback search_placeholder() :: String.t()

  @doc "Origins the browser calls for searches (CSP `connect-src`)."
  @callback api_sources() :: [String.t()]

  @doc "Origins the GIFs load from, in the overlay and in messages (CSP `img-src`)."
  @callback media_sources() :: [String.t()]

  @doc "The content filters the provider offers, safest last."
  @callback content_filters() :: [String.t()]
end
