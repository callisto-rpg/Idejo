# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.EmailLive do
  @moduledoc """
  Admin panel: outgoing email (AD-08). SMTP server, sender address, and a button that sends
  a test email to the signed-in administrator.
  """
  use IdejoWeb, :live_view

  alias Idejo.Accounts.UserNotifier
  alias Idejo.Settings

  @keys ~w(mail_from smtp_host smtp_port smtp_security smtp_username smtp_password)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Email"))
     |> assign(:sending?, false)
     |> assign_form(Settings.change_settings())}
  end

  defp assign_form(socket, changeset) do
    socket
    |> assign(:form, to_form(changeset, as: :settings))
    |> assign(:password_saved?, Settings.secret_set?(:smtp_password))
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset =
      params |> Map.take(@keys) |> Settings.change_settings() |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :settings))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Settings.update_settings(socket.assigns.current_scope.user, Map.take(params, @keys)) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Email settings saved."))
         |> assign_form(Settings.change_settings())}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :settings))}
    end
  end

  def handle_event("send_test", _params, socket) do
    recipient = socket.assigns.current_scope.user.email

    {:noreply,
     socket
     |> assign(:sending?, true)
     |> start_async(:send_test, fn -> {recipient, UserNotifier.deliver_test_email(recipient)} end)}
  end

  @impl true
  def handle_async(:send_test, {:ok, {recipient, {:ok, _email}}}, socket) do
    {:noreply,
     socket
     |> assign(:sending?, false)
     |> put_flash(:info, gettext("Test email sent to %{email}.", email: recipient))}
  end

  def handle_async(:send_test, {:ok, {_recipient, {:error, reason}}}, socket) do
    {:noreply,
     socket
     |> assign(:sending?, false)
     |> put_flash(:error, describe_error(reason))}
  end

  def handle_async(:send_test, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:sending?, false)
     |> put_flash(:error, describe_error(reason))}
  end

  @doc false
  def describe_error(:smtp_not_configured),
    do: gettext("Set an SMTP host and save before sending a test email.")

  def describe_error(reason) do
    gettext("The test email could not be sent: %{reason}",
      reason: inspect(reason, limit: 8, printable_limit: 200)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:email}>
      <.header>
        {gettext("Email")}
        <:subtitle>
          {gettext("The server sends sign-up verification and other emails through this SMTP server.")}
        </:subtitle>
      </.header>

      <.form for={@form} id="email-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:mail_from]} type="email" label={gettext("Sender address")} required />
        <.input
          field={@form[:smtp_host]}
          type="text"
          label={gettext("SMTP host (leave empty to turn email off)")}
          placeholder="smtp.example.org"
          spellcheck="false"
        />
        <.input field={@form[:smtp_port]} type="number" label={gettext("Port")} min="1" max="65535" />
        <.input
          field={@form[:smtp_security]}
          type="select"
          label={gettext("Encryption")}
          options={[
            {gettext("STARTTLS (usually port 587)"), "starttls"},
            {gettext("TLS from the start (usually port 465)"), "tls"},
            {gettext("None — only for a relay on the same machine or network"), "none"}
          ]}
        />
        <.input
          field={@form[:smtp_username]}
          type="text"
          label={gettext("Username")}
          autocomplete="off"
          spellcheck="false"
        />
        <.input
          field={@form[:smtp_password]}
          type="password"
          label={
            if @password_saved?,
              do: gettext("Password (saved; leave empty to keep it)"),
              else: gettext("Password")
          }
          autocomplete="new-password"
          value=""
        />
        <.button class="btn btn-primary" phx-disable-with={gettext("Saving…")}>
          {gettext("Save")}
        </.button>
      </.form>

      <section class="mt-10 space-y-2" aria-labelledby="test-email-heading">
        <h2 id="test-email-heading" class="font-semibold">{gettext("Test")}</h2>
        <p>
          {gettext("Sends a test email to %{email} with the saved settings.",
            email: @current_scope.user.email
          )}
        </p>
        <button
          id="send-test-email"
          type="button"
          class="btn"
          phx-click="send_test"
          disabled={@sending?}
        >
          {if @sending?, do: gettext("Sending…"), else: gettext("Send test email")}
        </button>
      </section>
    </Layouts.admin>
    """
  end
end
