# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSettingsLive do
  @moduledoc """
  Profile and account (AC-04): the signed-in user changes their display name. The avatar
  comes with uploads (M4); deleting the account with AC-07.
  """
  use IdejoWeb, :live_view

  alias Idejo.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, gettext("Profile and account"))
     |> assign(:form, to_form(Accounts.change_user_profile(user), as: :profile))}
  end

  @impl true
  def handle_event("validate", %{"profile" => params}, socket) do
    changeset =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :profile))}
  end

  def handle_event("save", %{"profile" => params}, socket) do
    case Accounts.update_user_profile(socket.assigns.current_scope.user, params) do
      {:ok, _user} ->
        # A full page load, so the header shows the new name too.
        {:noreply,
         socket
         |> put_flash(:info, gettext("Profile saved."))
         |> redirect(to: ~p"/users/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :profile))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("Profile and account")}
        <:subtitle>@{@current_scope.user.username} · {@current_scope.user.email}</:subtitle>
      </.header>

      <.form for={@form} id="profile-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:display_name]}
          type="text"
          label={gettext("Display name (shown above your messages)")}
          required
          maxlength="60"
        />
        <.button class="btn btn-primary">{gettext("Save")}</.button>
      </.form>
    </Layouts.app>
    """
  end
end
