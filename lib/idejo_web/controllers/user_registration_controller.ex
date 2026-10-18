# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserRegistrationController do
  use IdejoWeb, :controller

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias IdejoWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, page_title: gettext("Create an account"), changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, confirmation_flash(user))
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, page_title: gettext("Create an account"), changeset: changeset)
    end
  end

  defp confirmation_flash(user) do
    case Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}")) do
      {:ok, _} ->
        gettext("Welcome! We sent a link to %{email}; open it to verify your email address.",
          email: user.email
        )

      {:error, _} ->
        gettext(
          "Welcome! We could not send the verification email. Please try again in a moment."
        )
    end
  end
end
