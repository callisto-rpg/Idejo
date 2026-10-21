# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserResetPasswordController do
  @moduledoc """
  Password reset by email (AC-02). Asking for a link never says whether the email has an
  account. Setting a new password ends every session of the account (SP-02).
  """
  use IdejoWeb, :controller

  # SP-05: reset emails and attempts are limited per IP address.
  plug IdejoWeb.Plugs.RateLimit, :reset_password when action in [:create, :update]

  alias Idejo.Accounts
  alias IdejoWeb.UserAuth

  plug :get_user_by_reset_password_token when action in [:edit, :update]

  def new(conn, _params) do
    render(conn, :new,
      page_title: gettext("Reset your password"),
      form: Phoenix.Component.to_form(%{}, as: "user")
    )
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset-password/#{&1}")
      )
    end

    conn
    |> put_flash(
      :info,
      gettext(
        "If that email has an account, a link to reset its password is on its way. It works for one day."
      )
    )
    |> redirect(to: ~p"/users/sign-in")
  end

  def edit(conn, _params) do
    render_edit(conn, Accounts.change_user_password(conn.assigns.user))
  end

  def update(conn, %{"user" => user_params}) do
    case Accounts.reset_user_password(conn.assigns.user, user_params) do
      {:ok, {_user, socket_ids}} ->
        UserAuth.disconnect_sessions(socket_ids)

        conn
        |> put_flash(:info, gettext("Password changed. Sign in with your new password."))
        |> redirect(to: ~p"/users/sign-in")

      {:error, changeset} ->
        render_edit(conn, changeset)
    end
  end

  defp render_edit(conn, changeset) do
    render(conn, :edit,
      page_title: gettext("Choose a new password"),
      token: conn.params["token"],
      form: Phoenix.Component.to_form(changeset, as: "user")
    )
  end

  defp get_user_by_reset_password_token(conn, _opts) do
    if user = Accounts.get_user_by_reset_password_token(conn.params["token"]) do
      assign(conn, :user, user)
    else
      conn
      |> put_flash(:error, gettext("This reset link is invalid or has expired."))
      |> redirect(to: ~p"/users/reset-password")
      |> halt()
    end
  end
end
