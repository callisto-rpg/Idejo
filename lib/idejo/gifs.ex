# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Gifs do
  @moduledoc """
  GIFs in the composer (steward decisions, 2026-11-03): `!gif` and the graphical composer's
  GIF button open an overlay that searches a GIF provider from the browser and puts the
  chosen GIF at the caret, as Markdown. The provider is a module of
  `Idejo.Gifs.Provider`, set by `config :idejo, :gif_provider` (KLIPY by default), so it can
  be swapped.

  Off until an administrator enters the provider's key ("GIF provider key", Admin →
  Settings, `gif_api_key`); "GIF content filter" (`gif_content_filter`) sets the provider's
  safety filter. The key is not a secret: every browser that searches receives it. While on,
  readers' browsers load posted GIFs from the provider (a departure from SP-04, chosen by the
  steward), and the content security policy allows only the provider's hosts.
  """

  alias Idejo.Settings

  @doc "The provider module."
  @spec provider() :: module()
  def provider, do: Application.get_env(:idejo, :gif_provider, Idejo.Gifs.Klipy)

  @doc "Whether GIFs are on: a provider key is set."
  @spec enabled?() :: boolean()
  def enabled?, do: key() != ""

  defp key, do: String.trim(Settings.get(:gif_api_key))

  @doc """
  What the browser's overlay needs, or nil while GIFs are off: the adapter's `provider`
  id, the `key`, the content `filter`, the search box's `placeholder` and the provider's
  `name`, and the `hosts` its GIFs load from (the composer draws their Markdown as a pill).
  """
  @spec client_config() :: map() | nil
  def client_config do
    if enabled?() do
      provider = provider()

      %{
        provider: provider.id(),
        key: key(),
        filter: Settings.get(:gif_content_filter),
        placeholder: provider.search_placeholder(),
        name: provider.name(),
        hosts: provider.media_sources()
      }
    end
  end

  @doc """
  The origins the content security policy adds while GIFs are on: `connect` for the API,
  `img` for the GIFs. Empty while off.
  """
  @spec csp_sources() :: %{connect: [String.t()], img: [String.t()]}
  def csp_sources do
    if enabled?() do
      %{connect: provider().api_sources(), img: provider().media_sources()}
    else
      %{connect: [], img: []}
    end
  end

  @doc "The content filters the provider offers, for the setting."
  @spec content_filters() :: [String.t()]
  def content_filters, do: provider().content_filters()
end
