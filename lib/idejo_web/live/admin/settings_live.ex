# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.SettingsLive do
  @moduledoc """
  Admin panel: server-wide settings (AD-02), with the growing-message window (AD-04,
  GM-15). A new window applies to messages opened after the change; open messages keep the
  `closes_at` fixed at their first commit (GM-03).

  The website theme's colours (steward decision, 2026-10-24) are typed or picked with the
  browser's colour picker; the page loads again after they change, so the panel shows them.
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
  def handle_event("validate", %{"settings" => params} = all, socket) do
    changeset =
      params |> picked_colour(all) |> Settings.change_settings() |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :settings))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    theme = Settings.theme()

    case Settings.update_settings(socket.assigns.current_scope.user, params) do
      {:ok, _settings} ->
        socket = put_flash(socket, :info, gettext("Settings saved."))

        # The theme is in the root layout, which only a page load renders again.
        if Settings.theme() == theme do
          {:noreply, assign(socket, :form, to_form(Settings.change_settings(), as: :settings))}
        else
          {:noreply, redirect(socket, to: ~p"/admin")}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :settings))}
    end
  end

  # The colour picker fills in its hex field.
  defp picked_colour(params, %{"_target" => [_, target]}) do
    case String.replace_suffix(target, "_picker", "") do
      ^target -> params
      key -> Map.put(params, key, params[target])
    end
  end

  defp picked_colour(params, _all), do: params

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
          label={gettext("Patience timer (active thread) (seconds)")}
          min="0"
          max="600"
          step="1"
          aria-describedby="gm-window-help"
          required
        />
        <p id="gm-window-help" class="text-sm opacity-70 -mt-1 mb-4">
          {gettext(
            "How long after a message's first line its author must wait before Ctrl+Enter starts a new message. From 0 (no wait) to 600; messages already open keep their window."
          )}
        </p>
        <%!-- GM-05 (steward decision, 2026-10-23). --%>
        <.input
          field={@form[:gm_unanswered_minutes]}
          type="number"
          label={gettext("Patience timer (unanswered message) (minutes)")}
          min="1"
          max="1440"
          step="1"
          aria-describedby="gm-unanswered-help"
          required
        />
        <p id="gm-unanswered-help" class="text-sm opacity-70 -mt-1 mb-4">
          {gettext(
            "While nobody has written below a message, Ctrl+Enter starts a new one only once the message is this old; until then it adds a line to the same message, so someone writing alone keeps one message. From 1 to 1440 (a day)."
          )}
        </p>
        <%!-- Steward decision, 2026-10-24. --%>
        <.input
          field={@form[:gm_early_reply]}
          type="checkbox"
          label={gettext("Allow replies even if the timer is still running")}
          aria-describedby="gm-early-reply-help"
        />
        <p id="gm-early-reply-help" class="text-sm opacity-70 -mt-1 mb-4">
          {gettext(
            "Reply then starts a new message at any time, completing the author's open message. When off, a reply waits like Ctrl+Enter."
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
        <%!-- PN-19 --%>
        <.input
          field={@form[:push_enabled]}
          type="select"
          label={gettext("Push notifications")}
          options={[{gettext("On"), "on"}, {gettext("Off"), "off"}]}
        />
        <p class="text-sm opacity-70 -mt-1 mb-4">
          {gettext("When off, members are not offered browser notifications and none are sent.")}
        </p>
        <%!-- PN-04 --%>
        <.input
          field={@form[:push_followed_interval_minutes]}
          type="number"
          label={gettext("Minutes between followed-topic notifications")}
          min="1"
          max="1440"
          step="1"
          required
          aria-describedby="push-followed-help"
        />
        <p id="push-followed-help" class="text-sm opacity-70 -mt-1 mb-4">
          {gettext(
            "At most one \"new messages in topics you follow\" notification per member in this time."
          )}
        </p>
        <.input
          field={@form[:push_services]}
          type="textarea"
          label={gettext("Push services")}
          rows="4"
          aria-describedby="push-services-help"
        />
        <p id="push-services-help" class="text-sm opacity-70 -mt-1 mb-4">
          {gettext(
            "The only hosts browser notifications are sent to, one per line; *.example.org allows any name under example.org. The defaults are the services of Chrome, Edge, Firefox, Safari and Windows; add yours, for example a UnifiedPush server."
          )}
        </p>
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
        <%!-- The website theme (steward decision, 2026-10-24). --%>
        <fieldset class="theme-settings" aria-describedby="theme-help">
          <legend class="theme-settings-title">{gettext("Theme")}</legend>
          <p id="theme-help" class="text-sm opacity-70 mb-3">
            {gettext(
              "Buttons, toggles and links use the primary colour; the secondary and tertiary colours appear only where a second colour is needed. The backgrounds are the page's in the light and dark themes. As #rrggbb, or #rrggbbaa with transparency."
            )}
          </p>
          <.colour_setting
            :for={{key, label} <- theme_labels()}
            field={@form[key]}
            picker={@form[:"#{key}_picker"]}
            label={label}
          />
        </fieldset>
        <%!-- AD-02: the privacy notice at /privacy. --%>
        <.input
          field={@form[:privacy_notice]}
          type="textarea"
          label={gettext("Privacy notice (Markdown)")}
          rows="8"
          aria-describedby="privacy-notice-help"
        />
        <p id="privacy-notice-help" class="text-sm opacity-70 -mt-1 mb-4">
          {gettext("Shown on the Privacy page, linked from the foot of every page.")}
        </p>
        <.button class="btn btn-primary" phx-disable-with={gettext("Saving…")}>
          {gettext("Save")}
        </.button>
      </.form>
    </Layouts.admin>
    """
  end

  defp theme_labels do
    [
      theme_primary: gettext("Primary colour"),
      theme_secondary: gettext("Secondary colour"),
      theme_tertiary: gettext("Tertiary colour"),
      theme_light_bg: gettext("Light background"),
      theme_dark_bg: gettext("Dark background")
    ]
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :picker, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true

  # A hex field with the browser's colour picker beside it (which knows no transparency).
  defp colour_setting(assigns) do
    value = to_string(assigns.field.value)

    assigns =
      assign(assigns,
        swatch:
          if(Regex.match?(~r/^#[0-9a-fA-F]{6}/, value),
            do: String.downcase(String.slice(value, 0, 7)),
            else: "#000000"
          )
      )

    ~H"""
    <div class="theme-colour">
      <.input field={@field} type="text" label={@label} spellcheck="false" required />
      <label class="category-look-picker">
        <span class="sr-only">{gettext("Pick the %{colour}", colour: @label)}</span>
        <input type="color" name={@picker.name} id={@picker.id} value={@swatch} />
      </label>
    </div>
    """
  end
end
