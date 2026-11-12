# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InboxHTML do
  @moduledoc "The inbox's pages (steward request, 2026-11-10)."
  use IdejoWeb, :html

  alias IdejoWeb.TopicComponents

  embed_templates "inbox_html/*"

  attr :show, :atom, required: true, values: [:all, :unread]
  attr :view, :atom, required: true

  @doc """
  The Topics tab's "Show" toggle (steward request, 2026-11-10): "All my topics" or "Unread
  only", drawn like the View toggle beside it (joined buttons, the chosen one primary);
  links that keep the view, so no JavaScript is needed.
  """
  def show_toggle(assigns) do
    ~H"""
    <div class="view-toggle" id="show-toggle">
      <span class="view-toggle-label" id="show-toggle-label">{gettext("Show")}</span>
      <nav aria-labelledby="show-toggle-label" class="join">
        <a
          :for={{show, label} <- [all: gettext("All my topics"), unread: gettext("Unread only")]}
          href={~p"/topics?#{[show: show, view: @view]}"}
          id={"show-#{show}"}
          aria-current={@show == show && "true"}
          class={["btn btn-sm join-item", @show == show && "btn-primary"]}
        >
          {label}
        </a>
      </nav>
    </div>
    """
  end
end
