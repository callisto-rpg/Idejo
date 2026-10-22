# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.WelcomeController do
  @moduledoc """
  "Rules & Roles" (steward decision, 2026-10-23): `/rules` shows the server's About and Rules
  to anyone, and to signed-in members their self-select roles; `POST /welcome` saves those
  roles (`Idejo.Access.set_self_roles/2`) and marks the welcome card seen, then leads back to
  where the member was. Plain pages and forms, no JavaScript needed.
  """
  use IdejoWeb, :controller

  alias Idejo.Access
  alias Idejo.Accounts
  alias IdejoWeb.WelcomeComponents

  def show(conn, _params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    render(conn, :show,
      page_title: gettext("Rules & Roles"),
      data: WelcomeComponents.welcome_data(user)
    )
  end

  def update(conn, params) do
    user = conn.assigns.current_scope.user
    role_ids = params |> Map.get("role_ids", []) |> List.wrap() |> Enum.filter(&is_binary/1)
    {:ok, _roles} = Access.set_self_roles(user, role_ids)
    {:ok, _user} = Accounts.mark_welcomed(user)

    conn
    |> put_flash(:info, gettext("Welcome! Your roles are saved."))
    |> redirect(to: back(params["return_to"]))
  end

  # A path on this server only; anything else leads home.
  defp back("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: ~p"/", else: path
  end

  defp back(_), do: ~p"/"
end
