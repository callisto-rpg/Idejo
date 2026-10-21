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
    user = Accounts.get_user_by_email_and_password(email, password)

    cond do
      # MO-02: told only once the password is right, so nobody learns of a ban by guessing.
      user && Accounts.banned?(user) ->
        form = Phoenix.Component.to_form(Map.delete(user_params, "password"), as: "user")

        conn
        |> put_flash(:error, banned_message(user))
        |> render(:new, page_title: gettext("Sign in"), form: form)

      user ->
        conn
        |> put_flash(:info, gettext("Welcome back!"))
        |> UserAuth.log_in_user(user, user_params)

      true ->
        form = Phoenix.Component.to_form(Map.delete(user_params, "password"), as: "user")

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> render(:new, page_title: gettext("Sign in"), form: form)
    end
  end

  defp banned_message(%{banned_until: nil}), do: gettext("This account is banned.")

  defp banned_message(%{banned_until: until}),
    do:
      gettext("This account is banned until %{time}.",
        time: Calendar.strftime(until, "%Y-%m-%d %H:%M UTC")
      )

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Signed out."))
    |> UserAuth.log_out_user()
  end
end
