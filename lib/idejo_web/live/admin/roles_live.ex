# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.RolesLive do
  @moduledoc """
  Admin panel: the role editor (RP-02). Create custom roles with a name and a colour, rename
  them, change any role's colour, move roles up or down in rank, and delete custom roles.
  Owner and administrator stay on top and guest stays last.
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Access.Role
  alias IdejoWeb.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Roles"))
     |> assign(:editing, nil)
     |> assign(:new_form, to_form(Access.change_role(%Role{}), as: :role))
     |> load_roles()}
  end

  defp load_roles(socket) do
    assign(socket, roles: Access.list_roles(), holders: Access.holder_counts())
  end

  defp admin(socket), do: socket.assigns.current_scope.user
  defp find(socket, id), do: Enum.find(socket.assigns.roles, &(&1.id == id))

  @impl true
  def handle_event("validate_new", %{"role" => params}, socket) do
    changeset = %Role{} |> Access.change_role(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :new_form, to_form(changeset, as: :role))}
  end

  def handle_event("create", %{"role" => params}, socket) do
    case Access.create_role(admin(socket), params) do
      {:ok, role} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Role “%{name}” created.", name: role.name))
         |> assign(:new_form, to_form(Access.change_role(%Role{}), as: :role))
         |> load_roles()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset, as: :role))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    role = find(socket, id)
    {:noreply, assign(socket, :editing, {role.id, to_form(Access.change_role(role), as: :edit)})}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("update", %{"id" => id, "edit" => params}, socket) do
    case Access.update_role(admin(socket), find(socket, id), params) do
      {:ok, role} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Role “%{name}” saved.", name: Admin.role_name(role)))
         |> assign(:editing, nil)
         |> load_roles()}

      {:error, changeset} ->
        {:noreply, assign(socket, :editing, {id, to_form(changeset, as: :edit)})}
    end
  end

  def handle_event("move", %{"id" => id, "direction" => direction}, socket)
      when direction in ["up", "down"] do
    case Access.move_role(admin(socket), find(socket, id), String.to_existing_atom(direction)) do
      {:ok, _roles} ->
        {:noreply, load_roles(socket)}

      {:error, :fixed_rank} ->
        {:noreply, put_flash(socket, :error, gettext("This role cannot move further."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    role = find(socket, id)

    case Access.delete_role(admin(socket), role) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Role “%{name}” deleted.", name: role.name))
         |> load_roles()}

      {:error, :built_in} ->
        {:noreply, put_flash(socket, :error, gettext("Built-in roles cannot be deleted."))}
    end
  end

  # The first movable role cannot go up, the last movable one cannot go down.
  defp can_move?(roles, role, :up) do
    index = Enum.find_index(roles, &(&1.id == role.id))
    Access.movable?(role) and index > 0 and Access.movable?(Enum.at(roles, index - 1))
  end

  defp can_move?(roles, role, :down) do
    index = Enum.find_index(roles, &(&1.id == role.id))
    neighbour = Enum.at(roles, index + 1)
    Access.movable?(role) and neighbour != nil and Access.movable?(neighbour)
  end

  # TP-10: member and guest are never mentioned, so they take no mention settings.
  defp mentionable_kind?(%Role{built_in: true, name: name}), do: name not in ~w(member guest)
  defp mentionable_kind?(%Role{}), do: true

  attr :form, :any, required: true

  # TP-10 role mentions (+role): who may notify the role, and whom its members may notify.
  defp mention_settings(assigns) do
    ~H"""
    <.input
      field={@form[:mentionable]}
      type="select"
      label={gettext("Can be tagged by everyone")}
      options={[{gettext("No"), "false"}, {gettext("Yes"), "true"}]}
    />
    <.input
      field={@form[:mentions_below]}
      type="select"
      label={gettext("Can tag roles beneath")}
      options={[{gettext("No"), "false"}, {gettext("Yes"), "true"}]}
    />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:roles}>
      <.header>
        {gettext("Roles")}
        <:subtitle>
          {gettext(
            "Higher roles come first; a member's name takes the colour of their highest role. Owner and administrator always have every right."
          )}
        </:subtitle>
      </.header>

      <ol id="roles" class="space-y-2">
        <li
          :for={role <- @roles}
          id={"role-#{role.id}"}
          class="flex flex-wrap items-center gap-3 rounded border border-base-300 p-3"
        >
          <%= case @editing do %>
            <% {id, form} when id == role.id -> %>
              <.form
                for={form}
                id={"edit-role-#{role.id}"}
                phx-submit="update"
                phx-value-id={role.id}
                class="flex flex-wrap items-end gap-3 w-full"
              >
                <.input
                  :if={!role.built_in}
                  field={form[:name]}
                  type="text"
                  label={gettext("Name")}
                  required
                />
                <.input
                  field={form[:colour]}
                  type="text"
                  label={gettext("Colour (#rrggbb, empty for none)")}
                  placeholder="#3366ff"
                  spellcheck="false"
                />
                <.mention_settings :if={mentionable_kind?(role)} form={form} />
                <.button class="btn btn-primary btn-sm">{gettext("Save")}</.button>
                <button type="button" class="btn btn-sm" phx-click="cancel_edit">
                  {gettext("Cancel")}
                </button>
              </.form>
            <% _ -> %>
              <Admin.swatch colour={role.colour} />
              <span class="font-semibold">{Admin.role_name(role)}</span>
              <span :if={role.built_in} class="badge badge-sm">{gettext("built-in")}</span>
              <span :if={!role.built_in} class="text-sm opacity-70">
                {ngettext("1 member", "%{count} members", Map.get(@holders, role.id, 0))}
              </span>
              <span :if={mentionable_kind?(role)} class="text-sm opacity-70">
                <code>+{Access.role_slug(role)}</code>
                <span :if={role.mentionable}>· {gettext("can be tagged by everyone")}</span>
                <span :if={role.mentions_below}>· {gettext("can tag roles beneath")}</span>
              </span>
              <span class="flex-1"></span>
              <button
                :if={can_move?(@roles, role, :up)}
                type="button"
                class="btn btn-xs"
                phx-click="move"
                phx-value-id={role.id}
                phx-value-direction="up"
                aria-label={gettext("Move %{name} up", name: Admin.role_name(role))}
              >
                <.icon name="hero-arrow-up" />
              </button>
              <button
                :if={can_move?(@roles, role, :down)}
                type="button"
                class="btn btn-xs"
                phx-click="move"
                phx-value-id={role.id}
                phx-value-direction="down"
                aria-label={gettext("Move %{name} down", name: Admin.role_name(role))}
              >
                <.icon name="hero-arrow-down" />
              </button>
              <button
                type="button"
                class="btn btn-xs"
                phx-click="edit"
                phx-value-id={role.id}
                aria-label={gettext("Edit %{name}", name: Admin.role_name(role))}
              >
                {gettext("Edit")}
              </button>
              <button
                :if={!role.built_in}
                type="button"
                class="btn btn-xs btn-error"
                phx-click="delete"
                phx-value-id={role.id}
                data-confirm={
                  gettext("Delete the role “%{name}”? Its members lose it.", name: role.name)
                }
              >
                {gettext("Delete")}
              </button>
          <% end %>
        </li>
      </ol>

      <section class="mt-8" aria-labelledby="new-role-heading">
        <h2 id="new-role-heading" class="font-semibold mb-2">{gettext("New role")}</h2>
        <.form
          for={@new_form}
          id="new-role-form"
          phx-change="validate_new"
          phx-submit="create"
          class="flex flex-wrap items-end gap-3"
        >
          <.input field={@new_form[:name]} type="text" label={gettext("Name")} required />
          <.input
            field={@new_form[:colour]}
            type="text"
            label={gettext("Colour (#rrggbb, empty for none)")}
            placeholder="#3366ff"
            spellcheck="false"
          />
          <.mention_settings form={@new_form} />
          <.button class="btn btn-primary">{gettext("Create role")}</.button>
        </.form>
      </section>
    </Layouts.admin>
    """
  end
end
