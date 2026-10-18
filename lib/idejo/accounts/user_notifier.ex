# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.UserNotifier do
  @moduledoc """
  Account emails.
  """
  import Swoosh.Email
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Mailer
  alias Idejo.Settings

  # Sent from the server name and sender address set in the admin panel (AD-02, AD-08).
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({Settings.get(:server_name), Settings.get(:mail_from)})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver_email(email) do
      {:ok, email}
    end
  end

  @doc """
  Delivers the link that verifies a new account's email address (AC-01).
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      gettext("Verify your email address"),
      gettext(
        """
        Hi %{name},

        Please verify your email address by visiting the link below:

        %{url}

        If you didn't create an account, you can ignore this email.
        """,
        name: user.display_name,
        url: url
      )
    )
  end

  @doc """
  Delivers the link to set a new password (AC-02).
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(
      user.email,
      gettext("Reset your password"),
      gettext(
        """
        Hi %{name},

        Someone asked to reset the password of your account. To choose a new password,
        visit the link below within one day:

        %{url}

        If it wasn't you, you can ignore this email: your password stays the same.
        """,
        name: user.display_name,
        url: url
      )
    )
  end

  @doc """
  Sends a test email to the given address, to check the SMTP settings (AD-08).
  """
  def deliver_test_email(recipient) do
    deliver(
      recipient,
      gettext("Test email from %{name}", name: Settings.get(:server_name)),
      gettext("""
      This is a test email sent from the admin panel. Email from your server works.
      """)
    )
  end
end
