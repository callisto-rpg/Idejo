# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.PermissionsLive do
  @moduledoc """
  Admin panel: the permission grid (RP-04, RP-05). For the server, or for one category, each
  role gets allow, deny or unset for each right. Server-wide a right is only
  allowed or not; on a category, unset follows the role's server-wide setting and deny
  overrides it. Owner and administrator always have every right and take no settings.
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Access.Role
  alias Idejo.Forum
  alias IdejoWeb.Admin

  @effects %{"allow" => :allow, "deny" => :deny, "unset" => :unset}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Permissions"))
     |> assign(:roles, Access.list_roles())
     |> assign(:categories, Forum.list_categories())}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Forum.get_category_by_slug(slug) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("This category does not exist."))
         |> push_navigate(to: ~p"/admin/permissions")}

      category ->
        {:noreply, socket |> assign(:scope, category) |> load()}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, socket |> assign(:scope, :server) |> load()}

  defp load(socket) do
    scope = socket.assigns.scope
    server = Access.permissions(:server)

    assign(socket,
      settings: if(scope == :server, do: server, else: Access.permissions(scope)),
      server: server
    )
  end

  defp admin(socket), do: socket.assigns.current_scope.user

  @impl true
  def handle_event("set", %{"role" => role_id, "right" => right, "effect" => effect}, socket) do
    with %Role{} = role <- Enum.find(socket.assigns.roles, &(&1.id == role_id)),
         right when is_atom(right) <- Enum.find(Access.rights(), &(Atom.to_string(&1) == right)),
         {:ok, effect} <- Map.fetch(@effects, effect),
         {:ok, _} <-
           Access.set_permission(admin(socket), role, socket.assigns.scope, right, effect) do
      {:noreply, load(socket)}
    else
      _ ->
        {:noreply,
         socket |> put_flash(:error, gettext("This setting cannot be changed.")) |> load()}
    end
  end

  defp always_all_rights?(%Role{built_in: true, name: name}),
    do: name in ~w(owner administrator)

  defp always_all_rights?(%Role{}), do: false

  defp right_name(:view), do: gettext("View")
  defp right_name(:start), do: gettext("Start topics")
  defp right_name(:post), do: gettext("Post")
  defp right_name(:moderate), do: gettext("Moderate")
  defp right_name(:tag), do: gettext("Edit tags")

  defp effect(settings, role, right), do: Map.get(settings, {role.id, right}, :unset)

  defp scope_name(:server), do: gettext("Server-wide")
  defp scope_name(category), do: category.name

  # Server-wide, a right is allowed or not; on a category, unset says what it falls back to.
  defp options(:server, _server_effect),
    do: [{gettext("Not allowed"), "unset"}, {gettext("Allow"), "allow"}]

  defp options(_category, server_effect) do
    default =
      if server_effect == :allow,
        do: gettext("Server-wide (allowed)"),
        else: gettext("Server-wide (not allowed)")

    [{default, "unset"}, {gettext("Allow"), "allow"}, {gettext("Deny"), "deny"}]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:permissions}>
      <.header>
        {gettext("Permissions")}
        <:subtitle>
          {gettext(
            "Server-wide settings apply to every category. A category can allow or deny a right for one role instead. When any role of a user allows a right, the user has it. Owner and administrator always have every right."
          )}
        </:subtitle>
      </.header>

      <nav aria-label={gettext("Where the settings apply")} class="flex flex-wrap gap-2 mb-6">
        <.link
          patch={~p"/admin/permissions"}
          class={["btn btn-sm", @scope == :server && "btn-active"]}
          aria-current={@scope == :server && "page"}
        >
          {gettext("Server-wide")}
        </.link>
        <.link
          :for={category <- @categories}
          patch={~p"/admin/permissions/#{category.slug}"}
          class={["btn btn-sm", @scope != :server && @scope.id == category.id && "btn-active"]}
          aria-current={@scope != :server && @scope.id == category.id && "page"}
        >
          {category.name}
        </.link>
      </nav>

      <p :if={@categories == []} id="no-categories" class="mb-4 text-sm">
        {gettext("No categories yet; the server-wide settings will apply to each new category.")}
      </p>

      <div class="overflow-x-auto">
        <table id="permission-grid" class="table">
          <caption class="text-left font-semibold">{scope_name(@scope)}</caption>
          <thead>
            <tr>
              <th scope="col">{gettext("Role")}</th>
              <th :for={right <- Access.rights()} scope="col">{right_name(right)}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={role <- @roles} id={"role-#{role.id}"}>
              <th scope="row">{Admin.role_name(role)}</th>
              <%= if always_all_rights?(role) do %>
                <td :for={_right <- Access.rights()} class="opacity-70">{gettext("Always")}</td>
              <% else %>
                <td :for={right <- Access.rights()}>
                  <form id={"permission-#{role.id}-#{right}"} phx-change="set">
                    <input type="hidden" name="role" value={role.id} />
                    <input type="hidden" name="right" value={right} />
                    <select
                      name="effect"
                      class="select select-sm"
                      aria-label={
                        gettext("%{role}: %{right}",
                          role: Admin.role_name(role),
                          right: right_name(right)
                        )
                      }
                    >
                      {Phoenix.HTML.Form.options_for_select(
                        options(@scope, effect(@server, role, right)),
                        Atom.to_string(effect(@settings, role, right))
                      )}
                    </select>
                  </form>
                </td>
              <% end %>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.admin>
    """
  end
end
