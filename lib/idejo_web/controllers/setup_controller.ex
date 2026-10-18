# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SetupController do
  @moduledoc """
  The first-run wizard (AD-01): one page, no JavaScript needed. It needs the setup code from
  the app log, creates the owner, saves the server name and email settings, then signs the
  owner in.
  """
  use IdejoWeb, :controller

  alias Idejo.Setup
  alias IdejoWeb.UserAuth

  plug :refuse_when_set_up

  def new(conn, params) do
    render_form(conn, Setup.change(), params["code"] || "")
  end

  def create(conn, %{"setup" => %{"code" => code} = params}) do
    owner = Map.get(params, "owner", %{})
    settings = Map.get(params, "settings", %{})

    case Setup.complete(code, owner, settings) do
      {:ok, owner} ->
        conn
        |> put_flash(
          :info,
          gettext("Welcome! The server is set up. Send a test email to check email works.")
        )
        |> put_session(:user_return_to, ~p"/admin/email")
        |> UserAuth.log_in_user(owner)

      {:error, :invalid_code} ->
        conn
        |> put_flash(:error, gettext("The setup code is wrong. Copy it again from the app log."))
        |> render_form(Setup.change(owner, settings), "")

      {:error, :already_set_up} ->
        conn |> put_flash(:error, gettext("The server is already set up.")) |> redirect(to: ~p"/")

      {:error, forms} ->
        render_form(conn, forms, code)
    end
  end

  defp render_form(conn, %{owner: owner, settings: settings}, code) do
    render(conn, :new,
      page_title: gettext("Set up your server"),
      code: code,
      owner: Phoenix.Component.to_form(owner, as: "setup[owner]"),
      settings: Phoenix.Component.to_form(settings, as: "setup[settings]")
    )
  end

  defp refuse_when_set_up(conn, _opts) do
    if Setup.needed?() do
      conn
    else
      conn |> redirect(to: ~p"/") |> halt()
    end
  end
end
