# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSessionController do
  use IdejoWeb, :controller

  # SP-05: password guessing is slowed per IP address.
  plug IdejoWeb.Plugs.RateLimit, :sign_in when action == :create

  alias Idejo.Accounts
  alias Idejo.Accounts.OIDC
  alias IdejoWeb.UserAuth

  def new(conn, params) do
    render_new(conn, Phoenix.Component.to_form(%{}, as: "user"), params["with"] == "password")
  end

  # AC-09: with OpenID Connect, its button comes first; with IDEJO_LOCAL_ACCOUNTS=off, the
  # password form only on ?with=password, for owners and administrators.
  defp render_new(conn, form, asked_password? \\ true) do
    render(conn, :new,
      page_title: gettext("Sign in"),
      form: form,
      oidc?: OIDC.enabled?(),
      local_accounts?: OIDC.local_accounts?(),
      password?: OIDC.local_accounts?() or asked_password?
    )
  end

  # `Accounts.authenticate/2`: the password, whether the account may use one (AC-09), and a
  # ban, told only once the password is right (MO-02).
  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    case Accounts.authenticate(email, password) do
      {:error, {:banned, user}} ->
        form = Phoenix.Component.to_form(Map.delete(user_params, "password"), as: "user")

        conn
        |> put_flash(:error, banned_message(user))
        |> render_new(form)

      {:ok, user} ->
        conn
        |> put_flash(:info, gettext("Welcome back!"))
        |> UserAuth.log_in_user(user, user_params)

      {:error, :invalid} ->
        form = Phoenix.Component.to_form(Map.delete(user_params, "password"), as: "user")

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> render_new(form)
    end
  end

  @doc false
  # Also told by the OpenID Connect sign-in (AC-09).
  def banned_message(%{banned_until: nil}), do: gettext("This account is banned.")

  def banned_message(%{banned_until: until}),
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
