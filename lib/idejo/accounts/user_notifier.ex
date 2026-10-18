# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.UserNotifier do
  @moduledoc """
  Account emails.
  """
  import Swoosh.Email
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:idejo, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
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
end
