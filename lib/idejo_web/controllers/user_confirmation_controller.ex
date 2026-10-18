# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserConfirmationController do
  @moduledoc """
  Email verification (AC-01). Opening the link shows a button rather than verifying at
  once, so mail scanners that prefetch links do not verify the address.
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts

  def edit(conn, %{"token" => token}) do
    render(conn, :edit, token: token)
  end

  def update(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, gettext("Your email address is verified."))
        |> redirect(to: ~p"/")

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, gettext("This verification link is invalid or has expired."))
        |> redirect(to: ~p"/")
    end
  end

  # Sends a new link to the signed-in user.
  def create(conn, _params) do
    user = conn.assigns.current_scope.user

    {kind, message} =
      case Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}")) do
        {:ok, _} ->
          {:info, gettext("We sent a new link to %{email}.", email: user.email)}

        {:error, :already_confirmed} ->
          {:info, gettext("Your email address is already verified.")}

        {:error, _} ->
          {:error, gettext("We could not send the email. Please try again later.")}
      end

    conn
    |> put_flash(kind, message)
    |> redirect(to: ~p"/")
  end
end
