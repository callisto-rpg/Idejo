# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.PluginsLive do
  @moduledoc """
  Admin panel: plugins (steward request, 2026-11-08; `Idejo.Plugins`). Every file in the
  plugins folder, each with "Enabled" (off by default) and the roles that may use it, chosen
  in a dialog ("Add role"; owners and administrators always may), and "Add custom plugin",
  which uploads a plugin file into the folder. Deleting a file there removes its plugin.
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Plugins
  alias Idejo.Plugins.Definition
  alias IdejoWeb.Admin
  alias IdejoWeb.PluginComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Plugins"))
     |> assign(:roles, Access.list_roles())
     |> assign(choosing: nil, adding?: false, upload_error: nil)
     |> load()
     |> allow_upload(:plugin,
       accept: ~w(.json),
       max_entries: 1,
       max_file_size: Definition.max_bytes()
     )}
  end

  defp load(socket), do: assign(socket, :plugins, Plugins.list())

  defp admin(socket), do: socket.assigns.current_scope.user

  @impl true
  def handle_event("toggle", %{"command" => command} = params, socket) do
    enabled? = params["enabled"] == "true"

    case Plugins.set_enabled(admin(socket), command, enabled?) do
      {:ok, _} ->
        message =
          if enabled?,
            do: gettext("!%{command} is on.", command: command),
            else: gettext("!%{command} is off.", command: command)

        {:noreply, socket |> put_flash(:info, message) |> load()}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, gettext("This plugin is gone.")) |> load()}
    end
  end

  def handle_event("choose_roles", %{"command" => command}, socket),
    do: {:noreply, assign(socket, :choosing, command)}

  def handle_event("hide_roles", _params, socket), do: {:noreply, assign(socket, :choosing, nil)}

  def handle_event("save_roles", params, %{assigns: %{choosing: command}} = socket)
      when is_binary(command) do
    ids = for id <- List.wrap(params["role_ids"]), is_binary(id), do: id

    case Plugins.set_roles(admin(socket), command, ids) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:choosing, nil)
         |> put_flash(:info, gettext("Roles saved for !%{command}.", command: command))
         |> load()}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:choosing, nil)
         |> put_flash(:error, gettext("This plugin is gone."))
         |> load()}
    end
  end

  def handle_event("save_roles", _params, socket), do: {:noreply, socket}

  def handle_event("show_add", _params, socket),
    do: {:noreply, assign(socket, adding?: true, upload_error: nil)}

  def handle_event("hide_add", _params, socket), do: {:noreply, assign(socket, :adding?, false)}

  def handle_event("validate_plugin", _params, socket) do
    error =
      Enum.find_value(socket.assigns.uploads.plugin.entries, fn entry ->
        case upload_errors(socket.assigns.uploads.plugin, entry) do
          [:too_large | _] ->
            gettext("The file is larger than %{kb} KB.", kb: div(Definition.max_bytes(), 1024))

          [:not_accepted | _] ->
            gettext("Choose a .json plugin file.")

          _ ->
            nil
        end
      end)

    {:noreply, assign(socket, :upload_error, error)}
  end

  # The path is LiveView's own temporary file for the upload.
  # sobelow_skip ["Traversal.FileModule"]
  def handle_event("install", _params, socket) do
    results =
      consume_uploaded_entries(socket, :plugin, fn %{path: path}, _entry ->
        {:ok, Plugins.install(admin(socket), File.read!(path))}
      end)

    case results do
      [{:ok, definition}] ->
        {:noreply,
         socket
         |> assign(adding?: false, upload_error: nil)
         |> put_flash(
           :info,
           gettext("!%{command} is installed. Turn it on to use it.", command: definition.command)
         )
         |> load()}

      [{:error, reason}] ->
        {:noreply, assign(socket, :upload_error, PluginComponents.problem(reason))}

      [] ->
        {:noreply, assign(socket, :upload_error, gettext("Choose a plugin file first."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:plugins}>
      <.header>
        {gettext("Plugins")}
        <:subtitle>
          {gettext(
            "Plugins add ! commands to the composer. Each is one file in the plugins folder; delete a file there to remove its plugin. Owners and administrators may use every plugin that is on; other roles only those you add."
          )}
        </:subtitle>
      </.header>

      <p :if={@plugins == []} id="no-plugins">{gettext("No plugins installed.")}</p>

      <ul :if={@plugins != []} id="plugins" class="space-y-2">
        <li
          :for={row <- @plugins}
          id={"plugin-#{row.definition && row.definition.command || row.file}"}
          class="rounded border border-base-300 p-3"
        >
          <%= if row.definition do %>
            <div class="flex flex-wrap items-center gap-3">
              <label class="flex items-center gap-2">
                <input
                  type="checkbox"
                  class="toggle toggle-primary toggle-sm"
                  checked={row.setting && row.setting.enabled}
                  disabled={row.error != nil}
                  phx-click="toggle"
                  phx-value-command={row.definition.command}
                  phx-value-enabled={to_string(!(row.setting && row.setting.enabled))}
                  aria-describedby={"plugin-#{row.definition.command}-about"}
                />
                <span class="font-semibold">
                  {gettext("Enabled")}
                </span>
              </label>
              <span class="font-semibold">{row.definition.name}</span>
              <code>!{row.definition.command}</code>
              <span class="text-sm opacity-70">{row.file}</span>
              <span class="flex-1"></span>
              <button
                :if={row.error == nil}
                type="button"
                class="btn btn-xs"
                phx-click="choose_roles"
                phx-value-command={row.definition.command}
                id={"plugin-#{row.definition.command}-roles"}
                aria-haspopup="dialog"
              >
                <.icon name="hero-plus" class="size-4" />{gettext("Add role")}
              </button>
            </div>
            <p id={"plugin-#{row.definition.command}-about"} class="text-sm mt-1">
              {row.definition.description}
            </p>
            <p :if={row.error == nil} class="text-sm mt-1">
              {gettext("Who may use it:")}
              {gettext("owners and administrators")}<span :for={role <- chosen(@roles, row.setting)}>,
              <Admin.role_label role={role} /></span>
            </p>
            <p :if={row.error} class="text-sm text-error mt-1">
              {PluginComponents.problem(row.error)}
            </p>
          <% else %>
            <p class="font-semibold">{row.file}</p>
            <p class="text-sm text-error">
              {gettext("Not a plugin Idejo can use: %{reason}",
                reason: PluginComponents.problem(row.error)
              )}
            </p>
          <% end %>
        </li>
      </ul>

      <div class="mt-6">
        <button
          :if={!@adding?}
          id="add-plugin"
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="show_add"
        >
          {gettext("Add custom plugin")}
        </button>
        <section :if={@adding?} id="add-plugin-section" aria-labelledby="add-plugin-heading">
          <h2 id="add-plugin-heading" class="font-semibold mb-2">{gettext("Add custom plugin")}</h2>
          <p class="text-sm mb-2">
            {gettext(
              "A plugin is a .json file naming a command and one of the blocks Idejo draws: a video, a page in a frame, a link button or a card. It is installed turned off."
            )}
          </p>
          <.form for={%{}} id="plugin-upload-form" phx-change="validate_plugin" phx-submit="install">
            <label class="flex flex-col gap-1 text-sm mb-3">
              <span>{gettext("Plugin file (.json)")}</span>
              <.live_file_input upload={@uploads.plugin} class="file-input file-input-sm" />
            </label>
            <p
              :if={@upload_error}
              id="plugin-upload-error"
              role="alert"
              class="text-sm text-error mb-3"
            >
              {@upload_error}
            </p>
            <div class="flex gap-2">
              <.button class="btn btn-primary btn-sm">{gettext("Install")}</.button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="hide_add">
                {gettext("Cancel")}
              </button>
            </div>
          </.form>
        </section>
      </div>

      <.roles_dialog :if={@choosing} command={@choosing} roles={@roles} plugins={@plugins} />
    </Layouts.admin>
    """
  end

  defp chosen(_roles, nil), do: []

  defp chosen(roles, setting) do
    Enum.filter(roles, &(&1.id in setting.role_ids and not always?(&1)))
  end

  defp always?(role), do: role.built_in and role.name in ~w(owner administrator)

  attr :command, :string, required: true
  attr :roles, :list, required: true
  attr :plugins, :list, required: true

  defp roles_dialog(assigns) do
    row = Enum.find(assigns.plugins, &(&1.definition && &1.definition.command == assigns.command))
    held = if row && row.setting, do: row.setting.role_ids, else: []

    assigns =
      assign(assigns,
        held: held,
        choices: Enum.reject(assigns.roles, &always?/1)
      )

    ~H"""
    <dialog
      id="plugin-roles-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="hide_roles"
      data-return-focus
      aria-labelledby="plugin-roles-title"
    >
      <div class="modal-box">
        <h2 id="plugin-roles-title" class="inline-card-title">
          {gettext("Roles that may use !%{command}", command: @command)}
        </h2>
        <p class="text-sm mb-2">{gettext("Owners and administrators always may.")}</p>
        <.form for={%{}} id="plugin-roles-form" phx-submit="save_roles">
          <input type="hidden" name="role_ids[]" value="" />
          <fieldset>
            <legend class="sr-only">{gettext("Roles")}</legend>
            <label :for={role <- @choices} class="flex items-center gap-2 py-1">
              <input
                type="checkbox"
                name="role_ids[]"
                value={role.id}
                checked={role.id in @held}
                class="checkbox checkbox-sm"
              />
              <Admin.role_label role={role} />
            </label>
          </fieldset>
          <div class="modal-action">
            <button class="btn btn-sm btn-primary">{gettext("Save")}</button>
            <button type="button" class="btn btn-sm btn-ghost" phx-click="hide_roles">
              {gettext("Cancel")}
            </button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end
end
