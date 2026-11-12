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
  The Topics tab's "Unread only" switch (steward requests, 2026-11-10 and 2026-11-12): one
  link drawn as a switch (`role="switch"`, `aria-checked`) that turns to the other choice,
  all followed topics or only those with unread messages, keeping the view; no JavaScript.
  """
  def unread_switch(assigns) do
    ~H"""
    <a
      id="unread-switch"
      href={~p"/topics?#{[show: if(@show == :unread, do: :all, else: :unread), view: @view]}"}
      role="switch"
      aria-checked={to_string(@show == :unread)}
      class="inbox-switch"
    >
      <span class="inbox-switch-track" aria-hidden="true"></span>
      <span>{gettext("Unread only")}</span>
    </a>
    """
  end

  attr :forums, :list, required: true, doc: "`%{name:, host:, logo:}`, by name"
  attr :hidden, :list, required: true, doc: "the hosts of the forums whose topics are hidden"
  attr :show, :atom, required: true
  attr :view, :atom, required: true

  @doc """
  The Topics tab's "Filter" (steward request, 2026-11-12): the app's dropdown look over a
  checkbox per forum, ticked when its topics show, and Apply; a plain GET form
  (`filter=1`, `forums[]`), so it works without JavaScript.
  """
  def forum_filter(assigns) do
    hidden_count = Enum.count(assigns.forums, &(&1.host in assigns.hidden))
    assigns = assign(assigns, :hidden_count, hidden_count)

    ~H"""
    <form id="forum-filter" action={~p"/topics"} method="get" class="inbox-filter">
      <input type="hidden" name="filter" value="1" />
      <input type="hidden" name="show" value={@show} />
      <input type="hidden" name="view" value={@view} />
      <details id="forum-filter-menu" class="dropdown-select is-small" data-dropdown>
        <summary class="dropdown-select-button">
          <span class="dropdown-select-value">
            {gettext("Filter")}
            <span :if={@hidden_count > 0} id="forum-filter-hidden" class="badge badge-sm">
              {ngettext("1 hidden", "%{count} hidden", @hidden_count)}
            </span>
          </span>
        </summary>
        <fieldset class="popup-menu dropdown-select-menu inbox-filter-menu">
          <legend class="sr-only">{gettext("Show topics from")}</legend>
          <label :for={forum <- @forums} class="dropdown-select-option">
            <input
              type="checkbox"
              name="forums[]"
              value={forum.host}
              checked={forum.host not in @hidden}
            />
            <img src={forum.logo} alt="" class="inbox-filter-logo" loading="lazy" />
            {forum.name}
          </label>
          <button id="forum-filter-apply" class="inbox-filter-apply">{gettext("Apply")}</button>
        </fieldset>
      </details>
    </form>
    """
  end
end
