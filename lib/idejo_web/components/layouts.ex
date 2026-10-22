# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use IdejoWeb, :html

  alias Idejo.Forum.CategoryIcons

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :width, :atom,
    values: [:narrow, :wide],
    default: :narrow,
    doc: "the content column: narrow for reading, wide for grids and tables"

  attr :category, :any, default: nil, doc: "the category shown, marked in the sidebar"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :user, assigns.current_scope && assigns.current_scope.user)

    ~H"""
    <header class="app-header">
      <%!-- Shown and wired by assets/js/sidebar.js: without JavaScript the sidebar stays
           open on wide screens, and the home page lists the categories anyway. --%>
      <button
        type="button"
        id="sidebar-toggle"
        class="sidebar-toggle btn btn-ghost btn-sm btn-square"
        aria-controls="sidebar"
        aria-expanded="true"
        aria-label={gettext("Show or hide the categories")}
      >
        <.icon name="hero-bars-3" class="size-5" />
      </button>

      <a href={~p"/"} class="brand" id="brand">
        <span class="brand-mark" aria-hidden="true">{brand_initial()}</span>
        <span class="brand-name">{server_name()}</span>
      </a>

      <form action={~p"/search"} method="get" role="search" class="header-search">
        <label for="header-search-q" class="sr-only">{gettext("Search")}</label>
        <.icon name="hero-magnifying-glass" class="size-4 header-search-icon" />
        <input
          type="search"
          name="q"
          id="header-search-q"
          placeholder={gettext("Search")}
          class="header-search-input"
        />
      </form>

      <nav aria-label={gettext("Site")} class="header-nav">
        <a
          href={~p"/search"}
          id="search-link"
          class="header-icon md:hidden"
          aria-label={gettext("Search")}
        >
          <.icon name="hero-magnifying-glass" class="size-5" />
        </a>
        <%!-- TP-07: topics with something new, across categories. --%>
        <a :if={@user} href={~p"/unread"} id="unread-link" class="header-link">
          <.icon name="hero-inbox-stack" class="size-5" />
          <span class="header-link-text">{gettext("Unread")}</span>
        </a>
        <.moderation_link :if={@user} user={@user} />
        <.notifications_link :if={@user} user={@user} />
      </nav>

      <.account_menu current_scope={@current_scope} />
    </header>

    <div class="app-body">
      <.sidebar user={@user} current={@category} />

      <div class="app-column">
        <div
          :if={@user && !Idejo.Accounts.confirmed?(@user)}
          role="status"
          class="verify-banner"
        >
          <.icon name="hero-envelope" class="size-5 shrink-0" />
          <p class="grow">
            {gettext("Please verify your email address to take part. Check your inbox for the link.")}
          </p>
          <.form for={%{}} action={~p"/users/confirm"}>
            <button class="btn btn-sm">{gettext("Send the link again")}</button>
          </.form>
        </div>

        <%!-- AX-01: the skip link's target; tabindex lets it take the focus in every browser. --%>
        <main id="main" tabindex="-1" class="app-main focus:outline-none">
          <div class={["mx-auto space-y-6", width_class(@width)]}>
            {render_slot(@inner_block)}
          </div>
        </main>

        <.site_footer />
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp width_class(:narrow), do: "max-w-3xl"
  defp width_class(:wide), do: "max-w-5xl"

  defp brand_initial, do: server_name() |> String.first() |> String.upcase()

  attr :current_scope, :map, required: true

  # The account menu: a <details> disclosure, so it opens without JavaScript.
  defp account_menu(assigns) do
    ~H"""
    <nav aria-label={gettext("Account")} class="account-nav">
      <%= if @current_scope && @current_scope.user do %>
        <details class="account-menu" id="account-menu">
          <summary class="account-summary">
            <IdejoWeb.UserComponents.avatar user={@current_scope.user} size={:small} />
            <span class="account-name">{@current_scope.user.display_name}</span>
            <.icon name="hero-chevron-down-micro" class="size-4 opacity-60" />
          </summary>
          <div class="account-panel">
            <p class="account-panel-who">
              <span class="font-medium">{@current_scope.user.display_name}</span>
              <span class="opacity-60">@{@current_scope.user.username}</span>
            </p>
            <ul>
              <li>
                <.link href={~p"/users/settings"} id="settings-link">
                  <.icon name="hero-user-circle" class="size-4" />
                  {gettext("Profile and account")}
                </.link>
              </li>
              <li :if={@current_scope.administrator?}>
                <.link href={~p"/admin"} id="admin-link">
                  <.icon name="hero-cog-6-tooth" class="size-4" />
                  {gettext("Admin")}
                </.link>
              </li>
              <li class="account-panel-theme">
                <span>{gettext("Theme")}</span>
                <.theme_toggle />
              </li>
              <li>
                <%!-- A form, not a data-method link, so signing out works without JavaScript. --%>
                <.form for={%{}} action={~p"/users/sign-out"} method="delete">
                  <button>
                    <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
                    {gettext("Sign out")}
                  </button>
                </.form>
              </li>
            </ul>
          </div>
        </details>
      <% else %>
        <%!-- On phones, the sidebar holds it: the header has no room. --%>
        <.theme_toggle class="max-sm:hidden" />
        <.link href={~p"/users/sign-in"} class="btn btn-ghost btn-sm">{gettext("Sign in")}</.link>
        <.link href={~p"/users/sign-up"} class="btn btn-primary btn-sm">
          {gettext("Sign up")}
        </.link>
      <% end %>
    </nav>
    """
  end

  attr :user, :any, required: true
  attr :current, :any, required: true

  # The categories the visitor may view, the most recently active first, each with the topics
  # the user follows in it (TP-13), oldest followed first. Hidden and shown by the header's
  # button (assets/js/sidebar.js), which the browser remembers.
  defp sidebar(assigns) do
    summaries =
      assigns.user
      |> Idejo.Forum.list_category_summaries()
      |> Enum.sort_by(&(&1.last_activity_at || ~U[1970-01-01 00:00:00Z]), {:desc, DateTime})

    followed =
      assigns.user |> Idejo.Reading.list_followed_topics() |> Enum.group_by(& &1.category_id)

    assigns = assign(assigns, summaries: summaries, followed: followed)

    ~H"""
    <aside id="sidebar" class="app-sidebar">
      <nav aria-label={gettext("Categories")} class="sidebar-nav">
        <p class="sidebar-heading">{gettext("Active categories")}</p>
        <ul :if={@summaries != []}>
          <li :for={%{category: category} = summary <- @summaries}>
            <a
              href={~p"/c/#{category.slug}"}
              class={[
                "sidebar-link",
                "cat-#{category.id}",
                @current && @current.id == category.id && "is-current"
              ]}
              aria-current={@current && @current.id == category.id && "page"}
            >
              <IdejoWeb.TopicComponents.category_mark category={category} size={:small} />
              <span class="sidebar-name">{category.name}</span>
              <span :if={summary.last_activity_at} class="sidebar-when">
                <IdejoWeb.TopicComponents.time_ago at={summary.last_activity_at} short />
              </span>
            </a>
            <.followed_topics topics={Map.get(@followed, category.id, [])} />
          </li>
        </ul>
        <p :if={@summaries == []} class="sidebar-empty">{gettext("No categories yet.")}</p>
        <a href={~p"/"} class="sidebar-link sidebar-all">
          <.icon name="hero-squares-2x2" class="size-4" />
          {gettext("All categories")}
        </a>
        <%!-- TP-19 --%>
        <a href={~p"/tags"} class="sidebar-link" id="tags-link">
          <.icon name="hero-tag" class="size-4" />
          {gettext("Filter by tag")}
        </a>
      </nav>
      <div :if={!@user} class="sidebar-theme sm:hidden">
        <span>{gettext("Theme")}</span>
        <.theme_toggle />
      </div>
    </aside>
    """
  end

  attr :topics, :list, required: true

  @followed_shown 4

  # The topics followed in one category: the first four, then the rest behind a "more topics"
  # disclosure (a <details>, so it opens without JavaScript).
  defp followed_topics(assigns) do
    {shown, more} = Enum.split(assigns.topics, @followed_shown)
    assigns = assign(assigns, shown: shown, more: more)

    ~H"""
    <ul :if={@topics != []} class="sidebar-topics">
      <.followed_topic :for={topic <- @shown} topic={topic} />
      <li :if={@more != []}>
        <details class="sidebar-more">
          <summary>
            <span class="sidebar-more-closed">
              {ngettext("1 more topic", "%{count} more topics", length(@more))}
            </span>
            <span class="sidebar-more-open">{gettext("Fewer topics")}</span>
          </summary>
          <ul class="sidebar-topics">
            <.followed_topic :for={topic <- @more} topic={topic} />
          </ul>
        </details>
      </li>
    </ul>
    """
  end

  attr :topic, :map, required: true

  # One followed topic, with an unfollow button shown on hover or focus (TP-13). A plain form
  # post: FollowController leads back to the page it came from.
  defp followed_topic(assigns) do
    ~H"""
    <li class="sidebar-topic">
      <a href={~p"/t/#{@topic.id}/#{@topic.slug}"} class="sidebar-topic-link">
        {@topic.title}
      </a>
      <.form
        for={%{}}
        action={~p"/t/#{@topic.id}/follow"}
        method="delete"
        class="sidebar-unfollow"
      >
        <input type="hidden" name="return" value="back" />
        <button
          type="submit"
          aria-label={gettext("Unfollow %{title}", title: @topic.title)}
          title={gettext("Unfollow")}
        >
          <.icon name="hero-x-mark-micro" class="size-3.5" />
        </button>
      </.form>
    </li>
    """
  end

  attr :nonce, :string, default: nil
  attr :user, :any, default: nil

  @doc """
  Each category's colour as a CSS variable, `--cat` on `.cat-{id}`, for the lines and glows
  of the elements that belong to it (RP-03): its own colour, or the tint its id gives it. Only
  the categories the visitor may view, so no other id reaches the page (AC-05). A `<style>`
  with the request's nonce: the CSP refuses `style` attributes (SP-05); the colours are checked
  `#rrggbb` and the ids UUIDs, so the rules hold nothing else.
  """
  def category_colours(assigns) do
    rules =
      for category <- Idejo.Forum.list_viewable_categories(assigns.user), into: "" do
        colour = category.colour || CategoryIcons.tint(category.id)
        ".cat-#{category.id}{--cat:#{colour}}"
      end

    assigns = assign(assigns, :rules, rules)

    ~H"""
    <style :if={@nonce && @rules != ""} nonce={@nonce}>
      <%= @rules %>
    </style>
    """
  end

  attr :user, :map, required: true

  # NO-01: the Notifications screen, with the unread count. Counted when the layout renders,
  # so it is current on each page; it does not change live on an open page.
  defp notifications_link(assigns) do
    assigns = assign(assigns, :count, Idejo.Notifications.unread_count(assigns.user))

    ~H"""
    <a href={~p"/notifications"} id="notifications-link" class="header-icon">
      <.icon name="hero-bell" class="size-5" />
      <span class="sr-only">{gettext("Notifications")}</span>
      <span :if={@count > 0} class="header-badge">
        {@count}<span class="sr-only">{gettext(" unread")}</span>
      </span>
    </a>
    """
  end

  attr :user, :map, required: true

  # MO-01, MO-03: the Moderation screen, for users who may moderate somewhere, with the number
  # of reported messages waiting.
  defp moderation_link(assigns) do
    assigns = assign(assigns, :reports, Idejo.Moderation.open_report_count(assigns.user))

    ~H"""
    <a
      :if={Idejo.Moderation.moderator?(@user)}
      href={~p"/moderation"}
      id="moderation-link"
      class="header-link"
    >
      <.icon name="hero-shield-check" class="size-5" />
      <span class="header-link-text">{gettext("Moderation")}</span>
      <span :if={@reports > 0} class="header-badge header-badge-warning">
        {@reports}<span class="sr-only">{gettext(" open reports")}</span>
      </span>
    </a>
    """
  end

  @doc """
  The footer on every page: the attribution notice (LI-02) and the "Source code" link
  (LI-03).

  The notice is kept word for word as NOTICE gives it, and is not translated: section 7(b)
  of the licence requires it to be preserved.
  """
  def site_footer(assigns) do
    ~H"""
    <footer class="site-footer">
      <a href="https://idejo.org" id="attribution">
        Powered by Idejo — © Mariano Pictet and contributors — AGPL-3.0
      </a>
      <a href={Idejo.Source.url()} id="source-code">{gettext("Source code")}</a>
    </footer>
    """
  end

  @doc """
  The name shown in the header and page titles: the server name set by an administrator
  (AD-02), or "Idejo" when none is set. When branding exists (AD-11), the Idejo logo will be
  the fallback in the same way.
  """
  @spec server_name() :: String.t()
  def server_name, do: Idejo.Settings.get(:server_name)

  @doc """
  The page title: "Page · Server name", or the server name alone.
  """
  attr :page_title, :string, default: nil

  def page_title(assigns) do
    assigns = assign(assigns, :server_name, server_name())

    ~H"""
    <.live_title
      default={@server_name}
      suffix={@page_title && " · " <> @server_name}
      phx-no-format
    >{@page_title}</.live_title>
    """
  end

  @doc """
  Renders the admin panel (AD-02): the app layout with the admin sections.

  ## Examples

      <Layouts.admin flash={@flash} current_scope={@current_scope} section={:settings}>
        <h1>Settings</h1>
      </Layouts.admin>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true

  attr :section, :atom,
    required: true,
    values: [:settings, :email, :users, :invites, :roles, :categories, :tags, :permissions]

  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width={:wide}>
      <nav aria-label={gettext("Admin")} class="tabs tabs-border mb-6 overflow-x-auto">
        <.link
          navigate={~p"/admin"}
          class={["tab", @section == :settings && "tab-active"]}
          aria-current={@section == :settings && "page"}
        >
          {gettext("Settings")}
        </.link>
        <.link
          navigate={~p"/admin/email"}
          class={["tab", @section == :email && "tab-active"]}
          aria-current={@section == :email && "page"}
        >
          {gettext("Email")}
        </.link>
        <.link
          navigate={~p"/admin/users"}
          class={["tab", @section == :users && "tab-active"]}
          aria-current={@section == :users && "page"}
        >
          {gettext("Users")}
        </.link>
        <.link
          navigate={~p"/admin/categories"}
          class={["tab", @section == :categories && "tab-active"]}
          aria-current={@section == :categories && "page"}
        >
          {gettext("Categories")}
        </.link>
        <.link
          navigate={~p"/admin/tags"}
          class={["tab", @section == :tags && "tab-active"]}
          aria-current={@section == :tags && "page"}
        >
          {gettext("Tags")}
        </.link>
        <.link
          navigate={~p"/admin/permissions"}
          class={["tab", @section == :permissions && "tab-active"]}
          aria-current={@section == :permissions && "page"}
        >
          {gettext("Permissions")}
        </.link>
        <.link
          navigate={~p"/admin/invites"}
          class={["tab", @section == :invites && "tab-active"]}
          aria-current={@section == :invites && "page"}
        >
          {gettext("Invites")}
        </.link>
        <.link
          navigate={~p"/admin/roles"}
          class={["tab", @section == :roles && "tab-active"]}
          aria-current={@section == :roles && "page"}
        >
          {gettext("Roles")}
        </.link>
      </nav>
      {render_slot(@inner_block)}
    </Layouts.app>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr :class, :any, default: nil

  def theme_toggle(assigns) do
    ~H"""
    <div role="group" aria-label={gettext("Theme")} class={["theme-toggle", @class]}>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label={gettext("Use the system's theme")}
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label={gettext("Use the light theme")}
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label={gettext("Use the dark theme")}
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
