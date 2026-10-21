# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use IdejoWeb, :html

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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href={~p"/"} class="text-lg font-semibold">{server_name()}</a>
      </div>
      <div class="flex-none flex items-center gap-4">
        <a href={~p"/search"} id="search-link" class="link">{gettext("Search")}</a>
        <%!-- TP-07: topics with something new, across categories. --%>
        <a
          :if={@current_scope && @current_scope.user}
          href={~p"/unread"}
          id="unread-link"
          class="link"
        >
          {gettext("Unread")}
        </a>
        <.notifications_link :if={@current_scope && @current_scope.user} user={@current_scope.user} />
        <.moderation_link :if={@current_scope && @current_scope.user} user={@current_scope.user} />
        <.theme_toggle />
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.site_footer />

    <.flash_group flash={@flash} />
    """
  end

  attr :user, :map, required: true

  # NO-01: the Notifications screen, with the unread count. Counted when the layout renders,
  # so it is current on each page; it does not change live on an open page.
  defp notifications_link(assigns) do
    assigns = assign(assigns, :count, Idejo.Notifications.unread_count(assigns.user))

    ~H"""
    <a href={~p"/notifications"} id="notifications-link" class="link">
      {gettext("Notifications")}
      <span :if={@count > 0} class="badge badge-sm badge-primary">
        {@count}<span class="sr-only">{gettext(" unread")}</span>
      </span>
    </a>
    """
  end

  attr :user, :map, required: true

  # MO-03: the Moderation screen, for users who may moderate somewhere.
  defp moderation_link(assigns) do
    ~H"""
    <a
      :if={Idejo.Moderation.moderator?(@user)}
      href={~p"/moderation/log"}
      id="moderation-link"
      class="link"
    >
      {gettext("Moderation")}
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
    <footer class="px-4 py-6 sm:px-6 lg:px-8 text-sm opacity-80">
      <p class="mx-auto max-w-2xl flex flex-wrap gap-x-4 gap-y-1">
        <a href="https://idejo.org" class="link" id="attribution">
          Powered by Idejo — © Mariano Pictet and contributors — AGPL-3.0
        </a>
        <a href={Idejo.Source.url()} class="link" id="source-code">{gettext("Source code")}</a>
      </p>
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
    values: [:settings, :email, :users, :invites, :roles, :categories, :permissions]

  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <nav aria-label={gettext("Admin")} class="tabs tabs-border mb-6">
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
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
