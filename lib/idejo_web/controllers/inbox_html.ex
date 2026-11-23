# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InboxHTML do
  @moduledoc "The inbox's pages (steward request, 2026-11-10)."
  use IdejoWeb, :html

  alias IdejoWeb.TopicComponents

  embed_templates "inbox_html/*"

  attr :count, :integer, required: true

  @doc """
  A forum card's "N new messages" (steward request, 2026-11-13): the unread messages in the
  topics the member follows there; nothing when none.
  """
  def forum_news(assigns) do
    ~H"""
    <p :if={@count > 0} class="inbox-forum-news">
      {ngettext("1 new message", "%{count} new messages", @count)}
    </p>
    """
  end

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

  @doc """
  The Forums tab's groups (steward request, 2026-11-23): `{id, title, forums}`, the
  favourites first under "Favourites", then the others; one group without a title when
  there are only favourites or none.
  """
  def forum_groups([]), do: []

  def forum_groups(communities) do
    case Enum.split_with(communities, & &1.favourite) do
      {[], others} ->
        [{"inbox-forums", nil, others}]

      {favourites, []} ->
        [{"inbox-favourites", gettext("Favourites"), favourites}]

      {favourites, others} ->
        [
          {"inbox-favourites", gettext("Favourites"), favourites},
          {"inbox-forums", gettext("Other forums"), others}
        ]
    end
  end

  attr :forum, :map, required: true, doc: "`%{name:, url:, favourite:}`"

  @doc """
  A forum card's top right corner (steward request, 2026-11-23): a heart on a favourite, and
  its menu, a `<details>` over a .popup-menu (so it opens without JavaScript): "Mark as
  favourite" (or "Remove from favourites") and "Leave forum", each a plain POST form.
  """
  def forum_menu(assigns) do
    name = assigns.forum.name

    assigns =
      assign(assigns,
        host: URI.parse(assigns.forum.url).host,
        leave_confirm:
          gettext("Leave %{name}? Your account and messages there are kept.", name: name)
      )

    ~H"""
    <div class="inbox-forum-corner">
      <span :if={@forum.favourite} class="inbox-forum-heart" title={gettext("Favourite")}>
        <.icon name="hero-heart-solid" class="size-4" />
        <span class="sr-only">{gettext("Favourite")}</span>
      </span>
      <details id={"inbox-forum-menu-" <> @host} class="inbox-forum-menu">
        <summary
          class="inbox-forum-menu-button"
          aria-label={gettext("Menu for %{name}", name: @forum.name)}
        >
          <.icon name="hero-ellipsis-vertical" class="size-5" />
        </summary>
        <div class="popup-menu has-arrow arrow-right inbox-forum-menu-panel">
          <ul>
            <li>
              <.form
                for={%{}}
                action={~p"/forums/favourite"}
                id={"inbox-forum-favourite-" <> @host}
              >
                <input type="hidden" name="host" value={@host} />
                <input type="hidden" name="favourite" value={to_string(!@forum.favourite)} />
                <button :if={!@forum.favourite}>
                  <.icon name="hero-heart" class="size-4" />
                  {gettext("Mark as favourite")}
                </button>
                <button :if={@forum.favourite}>
                  <.icon name="hero-heart-solid" class="size-4" />
                  {gettext("Remove from favourites")}
                </button>
              </.form>
            </li>
            <li>
              <.form for={%{}} action={~p"/forums/leave"} id={"inbox-forum-leave-" <> @host}>
                <input type="hidden" name="host" value={@host} />
                <button class="inbox-forum-leave" data-confirm={@leave_confirm}>
                  <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
                  {gettext("Leave forum")}
                </button>
              </.form>
            </li>
          </ul>
        </div>
      </details>
    </div>
    """
  end
end
