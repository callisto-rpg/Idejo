# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.UsersLive do
  @moduledoc """
  Admin panel: list of users, newest first (AD-02). Roles are assigned here from RP-06 and
  bans from MO-02.
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Users"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {page, ""} when page > 0 -> page
        _ -> 1
      end

    {users, more?} = Accounts.list_users(page: page)

    {:noreply,
     assign(socket,
       page: page,
       more?: more?,
       users: users,
       roles: Access.roles_of_users(users)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:users}>
      <.header>{gettext("Users")}</.header>

      <p :if={@users == []}>{gettext("No users on this page.")}</p>

      <.table :if={@users != []} id="users" rows={@users} row_id={&"user-#{&1.id}"}>
        <:col :let={user} label={gettext("Name")}>
          <.link navigate={~p"/admin/users/#{user.id}"} class="link">{user.display_name}</.link>
          <span class="opacity-70">@{user.username}</span>
        </:col>
        <:col :let={user} label={gettext("Email")}>
          {user.email}
          <span :if={is_nil(user.confirmed_at)} class="badge badge-warning badge-sm">
            {gettext("unverified")}
          </span>
        </:col>
        <:col :let={user} label={gettext("Roles")}>
          {@roles[user.id] |> Enum.map(&IdejoWeb.Admin.role_name/1) |> Enum.join(", ")}
        </:col>
        <:col :let={user} label={gettext("Joined")}>
          <time datetime={DateTime.to_iso8601(user.created_at)}>
            {Calendar.strftime(user.created_at, "%Y-%m-%d")}
          </time>
        </:col>
      </.table>

      <nav aria-label={gettext("Pages")} class="flex gap-4 mt-4">
        <.link :if={@page > 1} patch={~p"/admin/users?page=#{@page - 1}"} class="link">
          {gettext("Previous page")}
        </.link>
        <.link :if={@more?} patch={~p"/admin/users?page=#{@page + 1}"} class="link">
          {gettext("Next page")}
        </.link>
      </nav>
    </Layouts.admin>
    """
  end
end
