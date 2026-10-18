# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.UserLive do
  @moduledoc """
  Admin panel: one user's account details (AD-02).
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Accounts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = user <- Accounts.get_user(id) do
      {:ok,
       assign(socket,
         page_title: user.display_name,
         user: user,
         roles: Access.roles_of_users([user])[user.id]
       )}
    else
      _ -> raise Ecto.NoResultsError, queryable: Idejo.Accounts.User
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:users}>
      <.header>
        {@user.display_name}
        <:subtitle>@{@user.username}</:subtitle>
      </.header>

      <.list>
        <:item title={gettext("Email")}>{@user.email}</:item>
        <:item title={gettext("Email verified")}>
          {if @user.confirmed_at,
            do: Calendar.strftime(@user.confirmed_at, "%Y-%m-%d %H:%M UTC"),
            else: gettext("Not yet")}
        </:item>
        <:item title={gettext("Roles")}>
          {@roles |> Enum.map(&IdejoWeb.Admin.role_name/1) |> Enum.join(", ")}
        </:item>
        <:item title={gettext("Status")}>{@user.status}</:item>
        <:item title={gettext("Joined")}>
          {Calendar.strftime(@user.created_at, "%Y-%m-%d %H:%M UTC")}
        </:item>
        <:item title={gettext("URI")}><code>{@user.uri}</code></:item>
      </.list>

      <.link navigate={~p"/admin/users"} class="link">{gettext("Back to users")}</.link>
    </Layouts.admin>
    """
  end
end
