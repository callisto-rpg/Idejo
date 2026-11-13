# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Gifs.Klipy do
  @moduledoc """
  KLIPY (https://klipy.com) as the GIF provider (steward decision, 2026-11-03), on its
  standard terms (docs.klipy.com/integration-requirements): the browser calls the API and
  loads the GIFs from KLIPY's hosts, never through idejo, and shows the results as returned.
  The search box reads "Search KLIPY" (required by its attribution guidelines). The browser
  side is `assets/js/gifs/klipy.js`.
  """
  @behaviour Idejo.Gifs.Provider

  @impl true
  def id, do: "klipy"

  @impl true
  def name, do: "KLIPY"

  # The required wording, not translated (docs.klipy.com/attribution).
  @impl true
  def search_placeholder, do: "Search KLIPY"

  @impl true
  def api_sources, do: ["https://api.klipy.com"]

  # docs.klipy.com/network-requirements: media delivery.
  @impl true
  def media_sources,
    do: ["https://static.klipy.com", "https://static1.klipy.com", "https://static2.klipy.com"]

  @impl true
  def content_filters, do: ~w(off low medium high)
end
