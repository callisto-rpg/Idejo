# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.UserLive do
  @moduledoc """
  Admin panel: one user's account details (AD-02) and roles (RP-06). Administrators give and
  remove roles here; only owners give or remove the owner role.
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Accounts
  alias IdejoWeb.Admin
  alias IdejoWeb.UserAuth

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = user <- Accounts.get_user(id) do
      {:ok,
       socket
       |> assign(page_title: user.display_name, user: user)
       |> load_roles()}
    else
      _ -> raise Ecto.NoResultsError, queryable: Idejo.Accounts.User
    end
  end

  defp load_roles(socket) do
    admin = admin(socket)
    user = socket.assigns.user
    assigned = Access.assigned_roles(user)
    assigned_ids = MapSet.new(assigned, & &1.id)

    assign(socket,
      roles: Access.roles_of(user),
      assigned: assigned,
      addable:
        Enum.filter(
          Access.list_roles(),
          &(Access.assignable?(admin, &1) and not MapSet.member?(assigned_ids, &1.id))
        ),
      add_form: to_form(%{"role_id" => ""}, as: :assign)
    )
  end

  defp admin(socket), do: socket.assigns.current_scope.user

  @impl true
  def handle_event("assign", %{"assign" => %{"role_id" => role_id}}, socket) do
    with %{} = role <- Enum.find(socket.assigns.addable, &(&1.id == role_id)),
         {:ok, role} <- Access.assign_role(admin(socket), socket.assigns.user, role) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Role “%{name}” given.", name: Admin.role_name(role)))
       |> load_roles()}
    else
      error -> {:noreply, socket |> put_flash(:error, error_message(error)) |> load_roles()}
    end
  end

  def handle_event("unassign", %{"id" => role_id}, socket) do
    user = socket.assigns.user

    with %{} = role <- Enum.find(socket.assigns.assigned, &(&1.id == role_id)),
         {:ok, role} <- Access.unassign_role(admin(socket), user, role) do
      # Their open admin pages were allowed at mount; reconnecting checks again.
      if not Access.administrator?(user),
        do: UserAuth.disconnect_sessions(Accounts.session_socket_ids(user))

      {:noreply,
       socket
       |> put_flash(:info, gettext("Role “%{name}” removed.", name: Admin.role_name(role)))
       |> load_roles()}
    else
      error -> {:noreply, socket |> put_flash(:error, error_message(error)) |> load_roles()}
    end
  end

  defp error_message({:error, :last_owner}),
    do: gettext("The server must keep at least one owner.")

  defp error_message({:error, :own_administrator}),
    do: gettext("You cannot remove your own administrator role.")

  defp error_message({:error, :owner_only}),
    do: gettext("Only an owner can give or remove the owner role.")

  defp error_message(_), do: gettext("This role cannot be changed.")

  defp removable?(admin, user, role) do
    Access.assignable?(admin, role) and
      not (admin.id == user.id and role.built_in and role.name == "administrator")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:users}>
      <.header>
        <Admin.coloured_name roles={@roles}>{@user.display_name}</Admin.coloured_name>
        <:subtitle>@{@user.username}</:subtitle>
      </.header>

      <.list>
        <:item title={gettext("Email")}>{@user.email}</:item>
        <:item title={gettext("Email verified")}>
          {if @user.confirmed_at,
            do: Calendar.strftime(@user.confirmed_at, "%Y-%m-%d %H:%M UTC"),
            else: gettext("Not yet")}
        </:item>
        <:item title={gettext("Acts as")}>
          {@roles |> Enum.map(&Admin.role_name/1) |> Enum.join(", ")}
        </:item>
        <:item title={gettext("Status")}>{@user.status}</:item>
        <:item title={gettext("Joined")}>
          {Calendar.strftime(@user.created_at, "%Y-%m-%d %H:%M UTC")}
        </:item>
        <:item title={gettext("URI")}><code>{@user.uri}</code></:item>
      </.list>

      <section class="mt-8" aria-labelledby="roles-heading">
        <h2 id="roles-heading" class="font-semibold mb-2">{gettext("Roles")}</h2>
        <p class="text-sm mb-2">
          {if @user.confirmed_at,
            do: gettext("Every verified user is a member as well; these roles add to it."),
            else:
              gettext(
                "Until the email address is verified, this user acts as guest; only owner and administrator apply before that."
              )}
        </p>

        <p :if={@assigned == []} id="no-roles">{gettext("No roles given.")}</p>

        <ul id="assigned-roles" class="space-y-2">
          <li
            :for={role <- @assigned}
            id={"assigned-#{role.id}"}
            class="flex flex-wrap items-center gap-3 rounded border border-base-300 p-2"
          >
            <Admin.role_label role={role} class="font-semibold" />
            <span class="flex-1"></span>
            <button
              :if={removable?(@current_scope.user, @user, role)}
              type="button"
              class="btn btn-xs"
              phx-click="unassign"
              phx-value-id={role.id}
              data-confirm={
                gettext("Remove the role “%{role}” from %{user}?",
                  role: Admin.role_name(role),
                  user: @user.display_name
                )
              }
            >
              {gettext("Remove")}
            </button>
          </li>
        </ul>

        <.form
          :if={@addable != []}
          for={@add_form}
          id="assign-role-form"
          phx-submit="assign"
          class="flex flex-wrap items-end gap-3 mt-4"
        >
          <.input
            field={@add_form[:role_id]}
            type="select"
            label={gettext("Give a role")}
            options={Enum.map(@addable, &{Admin.role_name(&1), &1.id})}
          />
          <.button class="btn btn-primary">{gettext("Give role")}</.button>
        </.form>
      </section>

      <.link navigate={~p"/admin/users"} class="link mt-8 inline-block">
        {gettext("Back to users")}
      </.link>
    </Layouts.admin>
    """
  end
end
