# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSessionController do
  use IdejoWeb, :controller

  alias Idejo.Accounts
  alias IdejoWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new,
      page_title: gettext("Sign in"),
      form: Phoenix.Component.to_form(%{}, as: "user")
    )
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, gettext("Welcome back!"))
      |> UserAuth.log_in_user(user, user_params)
    else
      form = Phoenix.Component.to_form(Map.delete(user_params, "password"), as: "user")

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, gettext("Invalid email or password"))
      |> render(:new, page_title: gettext("Sign in"), form: form)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Signed out."))
    |> UserAuth.log_out_user()
  end
end
