# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.GifComponents do
  @moduledoc """
  The GIF overlay (steward decisions, 2026-11-03; `Idejo.Gifs`): `!gif` and the graphical
  composer's GIF button open it. The server renders only its frame: the `GifPicker` hook
  (`assets/js/gif_picker.js`) asks the provider from the browser, through its adapter
  (`assets/js/gifs/`), for the popular GIFs, then for what is typed in the search box, and
  puts the chosen one at the composer's caret as Markdown. Results show as the provider
  returns them (its terms), with "Powered by" its name.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  attr :gifs, :map, required: true, doc: "Idejo.Gifs.client_config/0"

  def gif_picker(assigns) do
    ~H"""
    <dialog
      id="gif-picker"
      class="modal"
      phx-hook="GifPicker"
      phx-update="ignore"
      aria-labelledby="gif-picker-title"
      data-provider={@gifs.provider}
      data-key={@gifs.key}
      data-filter={@gifs.filter}
      data-label-gif={gettext("GIF")}
    >
      <div class="modal-box gif-picker">
        <h2 id="gif-picker-title" class="inline-card-title">{gettext("Add a GIF")}</h2>
        <form class="gif-search" role="search" data-search>
          <label for="gif-search" class="sr-only">{gettext("Search GIFs")}</label>
          <input
            type="search"
            id="gif-search"
            placeholder={@gifs.placeholder}
            class="input input-sm w-full"
            autocomplete="off"
          />
        </form>
        <p class="inline-card-meta" data-status role="status">{gettext("Loading GIFs…")}</p>
        <p class="inline-card-meta" data-empty hidden>{gettext("No GIFs found.")}</p>
        <p class="inline-card-meta" data-failed hidden>
          {gettext("The GIFs could not be loaded. Try again in a moment.")}
        </p>
        <div class="gif-results" data-results role="group" aria-label={gettext("GIFs")}></div>
        <button type="button" class="btn btn-sm btn-ghost w-full" data-more hidden>
          {gettext("More GIFs")}
        </button>
        <div class="modal-action gif-picker-foot">
          <p class="gif-picker-credit">{gettext("Powered by %{name}", name: @gifs.name)}</p>
          <button type="button" class="btn btn-sm btn-ghost" data-close>
            {gettext("Close")}
          </button>
        </div>
      </div>
    </dialog>
    """
  end
end
