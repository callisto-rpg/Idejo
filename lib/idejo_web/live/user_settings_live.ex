# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSettingsLive do
  @moduledoc """
  Profile and account: the signed-in user changes their display name (AC-04) and password
  (AC-01). The avatar comes with uploads (M4); deleting the account with AC-07.
  """
  use IdejoWeb, :live_view

  alias Idejo.Accounts
  alias IdejoWeb.UserAuth

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, gettext("Profile and account"))
     |> assign(:session_token, session["user_token"])
     |> assign(:form, to_form(Accounts.change_user_profile(user), as: :profile))
     |> assign(:password_form, password_form(user))}
  end

  defp password_form(user, changeset \\ nil),
    do: to_form(changeset || Accounts.change_user_password(user), as: :password)

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

  def handle_event("validate_password", %{"password" => params}, socket) do
    changeset =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :password_form, password_form(nil, changeset))}
  end

  def handle_event("save_password", %{"password" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_password(user, params, socket.assigns.session_token) do
      {:ok, {user, socket_ids}} ->
        UserAuth.disconnect_sessions(socket_ids)

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Password changed. You were signed out everywhere else.")
         )
         |> assign(:password_form, password_form(user))}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, password_form(nil, changeset))}
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

      <section class="mt-10" aria-labelledby="password-heading">
        <h2 id="password-heading" class="font-semibold mb-2">{gettext("Change password")}</h2>
        <.form
          for={@password_form}
          id="password-form"
          phx-change="validate_password"
          phx-submit="save_password"
        >
          <.input
            field={@password_form[:current_password]}
            type="password"
            label={gettext("Current password")}
            autocomplete="current-password"
            required
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label={gettext("New password (at least 12 characters)")}
            autocomplete="new-password"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label={gettext("Repeat the new password")}
            autocomplete="new-password"
            required
          />
          <.button class="btn btn-primary">{gettext("Change password")}</.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
