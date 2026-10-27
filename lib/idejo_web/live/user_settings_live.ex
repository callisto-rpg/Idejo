# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSettingsLive do
  @moduledoc """
  Profile and account: the signed-in user changes their display name and avatar (AC-04),
  automatic punctuation, and password (AC-01), and can delete their account (AC-07).

  The avatar uploads as soon as a picture is chosen (`Idejo.Accounts.set_avatar/3`: a 256 px
  WebP square without metadata), and can be removed. So can a second picture for the dark
  theme, under "Dark mode picture", folded away until one is set (steward decision,
  2026-10-23).
  """
  use IdejoWeb, :live_view

  alias Idejo.Accounts
  alias Idejo.Notifications.Digest
  alias Idejo.Push
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
     |> assign(:writing_form, to_form(Accounts.change_user_writing(user), as: :writing))
     |> assign(:private_form, private_form(user))
     |> assign(:email_form, to_form(Digest.change_preferences(user), as: :email))
     |> assign(:push_on?, Push.enabled?())
     |> assign(:push_form, to_form(Push.change_preferences(user), as: :push))
     |> assign(:this_endpoint, nil)
     |> assign(:devices, Push.list_subscriptions(user))
     |> assign(:image_error, nil)
     |> allow_avatar(:avatar)
     |> allow_avatar(:dark_avatar)}
  end

  defp allow_avatar(socket, name) do
    allow_upload(socket, name,
      accept: Uploads.extensions(),
      max_entries: 1,
      max_file_size: Uploads.max_bytes(),
      auto_upload: true,
      progress: &avatar_progress/3
    )
  end

  # AC-04: a chosen picture becomes the avatar (or the dark theme's) as soon as it has uploaded.
  defp avatar_progress(name, entry, socket) do
    if entry.done? do
      user = socket.assigns.current_scope.user
      theme = if name == :dark_avatar, do: :dark, else: :light

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Accounts.set_avatar(user, path, theme)}
        end)

      case result do
        # A full page load, so the header and everything else show the new picture.
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, saved_text(theme))
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

  defp saved_text(:light), do: gettext("Avatar saved.")
  defp saved_text(:dark), do: gettext("Dark mode picture saved.")

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

  def handle_event("validate_dark_avatar", _params, socket),
    do: {:noreply, ImageUploads.check(socket, :dark_avatar)}

  def handle_event("remove_dark_avatar", _params, socket) do
    {:ok, _user} = Accounts.remove_avatar(socket.assigns.current_scope.user, :dark)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Dark mode picture removed."))
     |> redirect(to: ~p"/users/settings")}
  end

  def handle_event("remove_avatar", _params, socket) do
    {:ok, _user} = Accounts.remove_avatar(socket.assigns.current_scope.user)

    {:noreply,
     socket |> put_flash(:info, gettext("Avatar removed.")) |> redirect(to: ~p"/users/settings")}
  end

  # Receiving private messages (steward decision, 2026-10-27).
  def handle_event("save_private", %{"private" => params}, socket) do
    case Accounts.update_user_private_messages(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Private messages preference saved."))
         |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
         |> assign(:private_form, private_form(user))}

      {:error, changeset} ->
        {:noreply, assign(socket, :private_form, to_form(changeset, as: :private))}
    end
  end

  # Automatic punctuation (steward decision, 2026-10-26): open topic pages pick it up when
  # reloaded (`TopicLive` reads it at mount, for the composer and for the engine alike).
  def handle_event("save_writing", %{"writing" => params}, socket) do
    case Accounts.update_user_writing(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Writing preferences saved."))
         |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
         |> assign(:writing_form, to_form(Accounts.change_user_writing(user), as: :writing))}

      {:error, changeset} ->
        {:noreply, assign(socket, :writing_form, to_form(changeset, as: :writing))}
    end
  end

  # Email notifications (steward decision, 2026-10-23): the summary sent after a day away.
  def handle_event("save_email", %{"email" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Digest.update_preferences(user, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Email notifications saved."))
         |> assign(:email_form, to_form(Digest.change_preferences(user), as: :email))}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(changeset, as: :email))}
    end
  end

  # PN-24: push notifications. The `PushSettings` hook tells which subscription is this
  # browser's (`"push_endpoint"`) and when it subscribed (`"push_changed"`).
  def handle_event("save_push", %{"push" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Push.update_preferences(user, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Push notifications saved."))
         |> assign(:push_form, to_form(Push.change_preferences(user), as: :push))}

      {:error, changeset} ->
        {:noreply, assign(socket, :push_form, to_form(changeset, as: :push))}
    end
  end

  def handle_event("push_endpoint", %{"endpoint" => endpoint}, socket)
      when is_binary(endpoint) or is_nil(endpoint),
      do: {:noreply, assign(socket, :this_endpoint, endpoint)}

  def handle_event("push_changed", _params, socket),
    do: {:noreply, load_devices(socket)}

  def handle_event("remove_device", %{"id" => id}, socket) do
    case Push.remove_subscription(socket.assigns.current_scope.user, id) do
      {:ok, endpoint} ->
        socket = load_devices(socket)

        # This browser: its own subscription ends too, or the next page would save it again.
        socket =
          if endpoint == socket.assigns.this_endpoint,
            do: push_event(socket, "push_unsubscribe", %{}),
            else: socket

        {:noreply, put_flash(socket, :info, gettext("Device removed."))}

      {:error, :not_found} ->
        {:noreply, load_devices(socket)}
    end
  end

  def handle_event("send_test", _params, socket) do
    message =
      case Push.send_test(socket.assigns.current_scope.user) do
        {:ok, 0} -> {:error, gettext("No device takes notifications yet. Turn them on first.")}
        {:ok, _} -> {:info, gettext("Test notification sent.")}
        {:error, :rate_limited} -> {:error, gettext("Too many tests. Try again in a minute.")}
        {:error, _} -> {:error, gettext("The test notification could not be sent.")}
      end

    {:noreply, put_flash(socket, elem(message, 0), elem(message, 1))}
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

  defp load_devices(socket),
    do: assign(socket, :devices, Push.list_subscriptions(socket.assigns.current_scope.user))

  # A device as people know it, from the browser's user agent: "Firefox on Linux".
  @browsers [
    {"Edg/", "Edge"},
    {"OPR/", "Opera"},
    {"SamsungBrowser/", "Samsung Internet"},
    {"Firefox/", "Firefox"},
    {"FxiOS/", "Firefox"},
    {"CriOS/", "Chrome"},
    {"Chrome/", "Chrome"},
    {"Safari/", "Safari"}
  ]
  @systems [
    {"Android", "Android"},
    {"iPhone", "iPhone"},
    {"iPad", "iPad"},
    {"Windows", "Windows"},
    {"Mac OS X", "macOS"},
    {"CrOS", "ChromeOS"},
    {"Linux", "Linux"}
  ]

  defp private_form(user),
    do: to_form(Accounts.change_user_private_messages(user), as: :private)

  @doc false
  def device_name(user_agent) do
    agent = user_agent || ""
    browser = Enum.find_value(@browsers, &(String.contains?(agent, elem(&1, 0)) && elem(&1, 1)))
    system = Enum.find_value(@systems, &(String.contains?(agent, elem(&1, 0)) && elem(&1, 1)))

    case {browser, system} do
      {nil, nil} -> gettext("Unknown browser")
      {nil, system} -> system
      {browser, nil} -> browser
      {browser, system} -> gettext("%{browser} on %{system}", browser: browser, system: system)
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
        <.input
          field={@form[:user_tag]}
          type="text"
          label={gettext("User tag or nickname (shown after your name, optional)")}
          maxlength="32"
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

        <%!-- Steward decision, 2026-10-23: folded away until there is one. --%>
        <details
          id="dark-avatar"
          class="mt-4"
          open={@current_scope.user.avatar_dark_id != nil}
        >
          <summary class="cursor-pointer text-sm font-medium">{gettext("Dark mode picture")}</summary>
          <p class="text-sm opacity-70 mt-2 max-w-prose">
            {gettext(
              "Shown instead of your avatar to people using the dark theme. Without one, your avatar shows in both themes."
            )}
          </p>
          <div class="flex items-center gap-4 mt-2">
            <span :if={@current_scope.user.avatar_dark_id} class="avatar shrink-0" aria-hidden="true">
              <span class="w-12 rounded-full">
                <img src={Uploads.dark_avatar_url(@current_scope.user)} alt="" />
              </span>
            </span>
            <form
              id="dark-avatar-form"
              phx-change="validate_dark_avatar"
              phx-submit="validate_dark_avatar"
            >
              <label class="flex flex-col gap-1 text-sm">
                <span>{gettext("Choose a picture (JPEG, PNG, GIF or WebP)")}</span>
                <.live_file_input upload={@uploads.dark_avatar} class="file-input file-input-sm" />
              </label>
            </form>
            <button
              :if={@current_scope.user.avatar_dark_id}
              type="button"
              id="remove-dark-avatar"
              class="btn btn-sm"
              phx-click="remove_dark_avatar"
            >
              {gettext("Remove dark mode picture")}
            </button>
          </div>
        </details>
      </section>

      <section class="mt-10" aria-labelledby="writing-heading">
        <h2 id="writing-heading" class="font-semibold mb-2">{gettext("Writing")}</h2>
        <.form for={@writing_form} id="writing-form" phx-submit="save_writing">
          <.input
            field={@writing_form[:auto_punctuation]}
            type="checkbox"
            label={gettext("Automatic punctuation")}
            aria-describedby="auto-punctuation-help"
          />
          <p id="auto-punctuation-help" class="text-sm opacity-70 -mt-1 mb-4">
            {gettext(
              "Adds a full stop when a line is sent without punctuation at its end (never after code). When off, your messages keep the text exactly as typed."
            )}
          </p>
          <.button class="btn btn-primary">{gettext("Save writing preferences")}</.button>
        </.form>
      </section>

      <%!-- Steward decision, 2026-10-27. --%>
      <section class="mt-10" aria-labelledby="private-heading">
        <h2 id="private-heading" class="font-semibold mb-2">{gettext("Private messages")}</h2>
        <.form for={@private_form} id="private-form" phx-submit="save_private">
          <.input
            field={@private_form[:accepts_private_messages]}
            type="checkbox"
            label={gettext("Members can send me private messages")}
            aria-describedby="private-help"
          />
          <p id="private-help" class="text-sm opacity-70 -mt-1 mb-4">
            {gettext(
              "When off, nobody can start a private conversation with you or write to you in one."
            )}
          </p>
          <.button class="btn btn-primary">{gettext("Save private messages preference")}</.button>
        </.form>
      </section>

      <section class="mt-10" aria-labelledby="email-notifications-heading">
        <h2 id="email-notifications-heading" class="font-semibold mb-2">
          {gettext("Email notifications")}
        </h2>
        <.form for={@email_form} id="email-notifications-form" phx-submit="save_email">
          <fieldset class="mb-2">
            <legend class="mb-2">
              {gettext(
                "If I haven't logged in for 24 hours, send me a summary of activity if there are:"
              )}
            </legend>
            <.input
              field={@email_form[:mentions]}
              type="checkbox"
              label={
                gettext("@%{username} mentions and replies to my posts",
                  username: @current_scope.user.username
                )
              }
            />
            <.input
              field={@email_form[:role_mentions]}
              type="checkbox"
              label={gettext("+role mentions")}
            />
            <.input
              field={@email_form[:own_topics]}
              type="checkbox"
              label={gettext("New messages in a thread I created")}
            />
            <.input
              field={@email_form[:followed_topics]}
              type="checkbox"
              label={gettext("New messages in a thread I follow")}
            />
            <.input
              field={@email_form[:new_topics]}
              type="checkbox"
              label={gettext("New topics created")}
            />
            <.input
              field={@email_form[:all_activity]}
              type="checkbox"
              label={gettext("Any activity in the forum")}
            />
          </fieldset>
          <.input
            field={@email_form[:once_a_week]}
            type="checkbox"
            label={gettext("Don't send me a second message in the same week if I don't log in.")}
          />
          <.button class="btn btn-primary">{gettext("Save email notifications")}</.button>
        </.form>
      </section>

      <%!-- PN-24: push notifications (while the server has them on, PN-19). --%>
      <section :if={@push_on?} class="mt-10" aria-labelledby="push-notifications-heading">
        <h2 id="push-notifications-heading" class="font-semibold mb-2">
          {gettext("Push notifications")}
        </h2>
        <%!-- This browser's state, worked out by the PushSettings hook (assets/js/push_settings.js);
             without JavaScript, the "unknown" line stays. --%>
        <div
          id="push-browser"
          class="push-browser mb-4"
          phx-hook="PushSettings"
          phx-update="ignore"
          role="status"
        >
          <p class="push-browser-unknown">
            {gettext("Turning notifications on needs JavaScript.")}
          </p>
          <p class="push-browser-on" hidden>{gettext("Notifications are on in this browser.")}</p>
          <div class="push-browser-off" hidden>
            <p>{gettext("Notifications are off in this browser.")}</p>
            <button type="button" class="btn btn-sm btn-primary mt-2 push-browser-turn-on">
              {gettext("Turn on")}
            </button>
          </div>
          <p class="push-browser-blocked" hidden>
            {gettext(
              "Notifications are blocked in this browser. To allow them, open the site settings (the icon at the left of the address), set Notifications to Allow, then reload this page."
            )}
          </p>
          <p class="push-browser-ios" hidden>
            {gettext(
              "To get notifications on iPhone, add Idejo to your Home Screen: tap Share, then Add to Home Screen, then open it from there."
            )}
          </p>
          <p class="push-browser-unsupported" hidden>
            {gettext("This browser cannot show notifications.")}
          </p>
        </div>

        <.form for={@push_form} id="push-notifications-form" phx-submit="save_push">
          <fieldset class="mb-2">
            <legend class="mb-2">{gettext("Send me a notification for:")}</legend>
            <.input field={@push_form[:reply]} type="checkbox" label={gettext("Replies to me")} />
            <.input
              field={@push_form[:mention]}
              type="checkbox"
              label={gettext("@%{username} mentions", username: @current_scope.user.username)}
            />
            <.input
              field={@push_form[:role_mention]}
              type="checkbox"
              label={gettext("+role mentions")}
            />
            <.input
              field={@push_form[:followed]}
              type="checkbox"
              label={gettext("New messages in topics I follow")}
            />
            <.input
              field={@push_form[:private]}
              type="checkbox"
              label={gettext("Private messages")}
            />
          </fieldset>
          <p class="text-sm opacity-70 mb-3">{gettext("These apply to all your devices.")}</p>
          <.button class="btn btn-primary">{gettext("Save push notifications")}</.button>
        </.form>

        <h3 class="font-semibold mt-6 mb-2">{gettext("Devices")}</h3>
        <p :if={@devices == []} id="push-no-devices" class="text-sm opacity-70">
          {gettext("No device takes notifications yet.")}
        </p>
        <ul :if={@devices != []} id="push-devices" class="space-y-2">
          <li
            :for={device <- @devices}
            id={"push-device-#{device.id}"}
            class="flex flex-wrap items-center gap-3 rounded border border-base-300 p-3"
          >
            <span class="font-medium">{device_name(device.user_agent)}</span>
            <span :if={device.endpoint == @this_endpoint} class="badge badge-sm">
              {gettext("This browser")}
            </span>
            <span class="text-sm opacity-70">
              {gettext("Added %{date}", date: Calendar.strftime(device.created_at, "%Y-%m-%d"))}
            </span>
            <span class="flex-1"></span>
            <button
              type="button"
              class="btn btn-xs"
              phx-click="remove_device"
              phx-value-id={device.id}
              aria-label={gettext("Remove %{device}", device: device_name(device.user_agent))}
            >
              {gettext("Remove")}
            </button>
          </li>
        </ul>
        <button type="button" id="push-test" class="btn btn-sm mt-4" phx-click="send_test">
          {gettext("Send test notification")}
        </button>
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
