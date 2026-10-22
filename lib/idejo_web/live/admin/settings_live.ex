# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.SettingsLive do
  @moduledoc """
  Admin panel: server-wide settings (AD-02), with the growing-message window (AD-04,
  GM-15). A new window applies to messages opened after the change; open messages keep the
  `closes_at` fixed at their first commit (GM-03).
  """
  use IdejoWeb, :live_view

  alias Idejo.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Settings"))
     |> assign(:form, to_form(Settings.change_settings(), as: :settings))}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset = params |> Settings.change_settings() |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :settings))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Settings.update_settings(socket.assigns.current_scope.user, params) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Settings saved."))
         |> assign(:form, to_form(Settings.change_settings(), as: :settings))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :settings))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:settings}>
      <.header>{gettext("Settings")}</.header>

      <.form for={@form} id="settings-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:server_name]} type="text" label={gettext("Server name")} required />
        <.input
          field={@form[:registration_mode]}
          type="select"
          label={gettext("Who can sign up")}
          options={[
            {gettext("Anyone"), "open"},
            {gettext("Only people with an invite"), "invite_only"}
          ]}
        />
        <.input
          field={@form[:gm_window_seconds]}
          type="number"
          label={gettext("Growing-message window (seconds)")}
          min="10"
          max="600"
          step="1"
          aria-describedby="gm-window-help"
          required
        />
        <p id="gm-window-help" class="text-sm opacity-70 -mt-1 mb-4">
          {gettext(
            "How long after a message's first line its author must wait before Ctrl+Enter starts a new message. From 10 to 600; messages already open keep their window."
          )}
        </p>
        <.input
          field={@form[:upload_max_mb]}
          type="number"
          label={gettext("Largest image upload (MB)")}
          min="1"
          max="20"
          step="1"
          required
        />
        <%!-- The welcome card and "Rules & Roles" (steward decision, 2026-10-23). --%>
        <.input
          field={@form[:server_about]}
          type="textarea"
          label={gettext("About (Markdown)")}
          rows="5"
          aria-describedby="welcome-texts-help"
        />
        <.input
          field={@form[:server_rules]}
          type="textarea"
          label={gettext("Rules (Markdown)")}
          rows="8"
          aria-describedby="welcome-texts-help"
        />
        <p id="welcome-texts-help" class="text-sm opacity-70 -mt-1 mb-4">
          {gettext(
            "Shown to new members on their first visit, with the roles they may choose, and at any time under Rules & Roles."
          )}
        </p>
        <.button class="btn btn-primary" phx-disable-with={gettext("Saving…")}>
          {gettext("Save")}
        </.button>
      </.form>
    </Layouts.admin>
    """
  end
end
