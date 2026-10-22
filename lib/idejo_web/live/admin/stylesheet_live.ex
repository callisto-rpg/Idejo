# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.StylesheetLive do
  @moduledoc """
  Admin panel: the server's stylesheet (steward decision, 2026-10-23). Edit the CSS served at
  `/theme.css` after Idejo's own styles, save it, or reset it to the default
  (`priv/theme/default.css`). Saved through `Idejo.Settings` (`custom_css`), so each change
  is audited (SP-06).
  """
  use IdejoWeb, :live_view

  alias Idejo.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Stylesheet"))
     |> assign_form(Settings.get(:custom_css))}
  end

  defp assign_form(socket, css),
    do: assign(socket, :form, to_form(%{"custom_css" => css}, as: :theme))

  defp admin(socket), do: socket.assigns.current_scope.user

  @impl true
  def handle_event("save", %{"theme" => %{"custom_css" => css}}, socket) do
    save(socket, css, gettext("Stylesheet saved. Pages use it as they load."))
  end

  def handle_event("reset", _params, socket) do
    save(socket, Settings.default(:custom_css), gettext("Stylesheet reset to the default."))
  end

  defp save(socket, css, done) do
    case Settings.update_settings(admin(socket), %{"custom_css" => css}) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, done) |> assign_form(Settings.get(:custom_css))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("The stylesheet is too long (100,000 characters at most)."))
         |> assign_form(css)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:stylesheet}>
      <.header>
        {gettext("Stylesheet")}
        <:subtitle>
          {gettext(
            "CSS that every page loads after Idejo's own styles, so its rules win. Reset to default brings back the stylesheet Idejo came with."
          )}
        </:subtitle>
      </.header>

      <.form for={@form} id="stylesheet-form" phx-submit="save">
        <.input
          field={@form[:custom_css]}
          type="textarea"
          label={gettext("CSS")}
          rows="24"
          spellcheck="false"
          class="textarea w-full font-mono text-sm"
        />
        <div class="flex flex-wrap gap-2">
          <.button class="btn btn-primary" phx-disable-with={gettext("Saving…")}>
            {gettext("Save")}
          </.button>
          <button
            type="button"
            id="stylesheet-reset"
            class="btn"
            phx-click="reset"
            data-confirm={gettext("Replace the stylesheet with the default? Your changes are lost.")}
          >
            {gettext("Reset to default")}
          </button>
        </div>
      </.form>
    </Layouts.admin>
    """
  end
end
