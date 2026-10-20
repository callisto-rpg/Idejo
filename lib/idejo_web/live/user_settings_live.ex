# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSettingsLive do
  @moduledoc """
  Profile and account: the signed-in user changes their display name and avatar (AC-04)
  and password (AC-01), and can delete their account (AC-07).

  The avatar uploads as soon as a picture is chosen (`Idejo.Accounts.set_avatar/2`: a 256 px
  WebP square without metadata), and can be removed.
  """
  use IdejoWeb, :live_view

  alias Idejo.Accounts
  alias Idejo.Uploads
  alias IdejoWeb.ImageUploads
  alias IdejoWeb.UserAuth
  alias IdejoWeb.UserComponents

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, gettext("Profile and account"))
     |> assign(:session_token, session["user_token"])
     |> assign(:form, to_form(Accounts.change_user_profile(user), as: :profile))
     |> assign(:password_form, password_form(user))
     |> assign(:delete_form, to_form(%{"password" => ""}, as: :delete))
     |> assign(:image_error, nil)
     |> allow_upload(:avatar,
       accept: Uploads.extensions(),
       max_entries: 1,
       max_file_size: Uploads.max_bytes(),
       auto_upload: true,
       progress: &avatar_progress/3
     )}
  end

  # AC-04: a chosen picture becomes the avatar as soon as it has uploaded.
  defp avatar_progress(:avatar, entry, socket) do
    if entry.done? do
      user = socket.assigns.current_scope.user

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Accounts.set_avatar(user, path)}
        end)

      case result do
        # A full page load, so the header and everything else show the new picture.
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Avatar saved."))
           |> redirect(to: ~p"/users/settings")}

        {:error, :too_large} ->
          {:noreply, assign(socket, :image_error, gettext("This image is too large."))}

        {:error, :too_many_pixels} ->
          {:noreply, assign(socket, :image_error, gettext("This image has too many pixels."))}

        {:error, _} ->
          {:noreply,
           assign(
             socket,
             :image_error,
             gettext("Only JPEG, PNG, GIF and WebP images can be added.")
           )}
      end
    else
      {:noreply, socket}
    end
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

  def handle_event("validate_avatar", _params, socket),
    do: {:noreply, ImageUploads.check(socket, :avatar)}

  def handle_event("remove_avatar", _params, socket) do
    {:ok, _user} = Accounts.remove_avatar(socket.assigns.current_scope.user)

    {:noreply,
     socket |> put_flash(:info, gettext("Avatar removed.")) |> redirect(to: ~p"/users/settings")}
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

  def handle_event("delete_account", %{"delete" => %{"password" => password}}, socket) do
    own_socket_id = Accounts.session_socket_id(socket.assigns.session_token)

    case Accounts.delete_user(socket.assigns.current_scope.user, password) do
      {:ok, {_user, socket_ids}} ->
        # This page goes to the home page by itself; the other sessions are disconnected.
        UserAuth.disconnect_sessions(Enum.reject(socket_ids, &(&1 == own_socket_id)))

        {:noreply,
         socket
         |> put_flash(:info, gettext("Your account has been deleted."))
         |> redirect(to: ~p"/")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, delete_error(reason))
         |> assign(:delete_form, to_form(%{"password" => ""}, as: :delete))}
    end
  end

  defp delete_error(:invalid_password), do: gettext("That is not your current password.")

  defp delete_error(:last_owner),
    do:
      gettext(
        "You are the only owner of this server. Make someone else owner before deleting your account."
      )

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

      <section class="mt-10" aria-labelledby="avatar-heading">
        <h2 id="avatar-heading" class="font-semibold mb-2">{gettext("Avatar")}</h2>
        <div class="flex items-center gap-4">
          <UserComponents.avatar user={@current_scope.user} size={:medium} />
          <form id="avatar-form" phx-change="validate_avatar" phx-submit="validate_avatar">
            <label class="flex flex-col gap-1 text-sm">
              <span>{gettext("Choose a picture (JPEG, PNG, GIF or WebP)")}</span>
              <.live_file_input upload={@uploads.avatar} class="file-input file-input-sm" />
            </label>
          </form>
          <button
            :if={@current_scope.user.avatar_id}
            type="button"
            id="remove-avatar"
            class="btn btn-sm"
            phx-click="remove_avatar"
          >
            {gettext("Remove avatar")}
          </button>
        </div>
        <p :if={@image_error} role="alert" class="text-sm text-error mt-2">{@image_error}</p>
      </section>

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

      <section class="mt-10" aria-labelledby="delete-heading">
        <h2 id="delete-heading" class="font-semibold mb-2">{gettext("Delete account")}</h2>
        <p class="text-sm mb-2">
          {gettext(
            "Your email address, username, display name and password are removed and you are signed out everywhere. This cannot be undone."
          )}
        </p>
        <.form for={@delete_form} id="delete-account-form" phx-submit="delete_account">
          <.input
            field={@delete_form[:password]}
            type="password"
            label={gettext("Your password, to confirm")}
            autocomplete="current-password"
            required
          />
          <.button
            class="btn btn-error"
            data-confirm={gettext("Delete your account for good?")}
          >
            {gettext("Delete my account")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
