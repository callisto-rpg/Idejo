# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.IgnoreController do
  @moduledoc """
  AC-06: ignore a user, or stop, from their card (its page `/u/{id}` or a topic's dialog) or
  from Profile and account. Plain form posts; `return_to` leads back to the topic or to the
  settings page.
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts

  def create(conn, %{"id" => id} = params) do
    user = user!(id)

    case Accounts.ignore_user(conn.assigns.current_scope.user, user) do
      :ok ->
        conn
        |> put_flash(
          :info,
          gettext("You ignore %{name}: their messages are collapsed for you.",
            name: user.display_name
          )
        )
        |> redirect(to: back(params, user))

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("This account cannot be ignored."))
        |> redirect(to: back(params, user))
    end
  end

  def delete(conn, %{"id" => id} = params) do
    user = user!(id)
    :ok = Accounts.unignore_user(conn.assigns.current_scope.user, user)

    conn
    |> put_flash(:info, gettext("You no longer ignore %{name}.", name: user.display_name))
    |> redirect(to: back(params, user))
  end

  # Back to the topic the card was opened in, to Profile and account, or to the card's page.
  # Only those paths are followed, so the parameter can never send anyone to another site.
  defp back(%{"return_to" => "/users/settings"}, _user),
    do: IdejoWeb.UserSettingsLive.path("messages", "ignored-section")

  defp back(%{"return_to" => "/t/" <> rest = path}, user) do
    if Regex.match?(~r|\A[0-9a-f-]{36}(/[a-z0-9-]*)?\z|, rest), do: path, else: ~p"/u/#{user.id}"
  end

  defp back(_params, user), do: ~p"/u/#{user.id}"

  defp user!(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = user <- Accounts.get_user(id) do
      user
    else
      _ -> raise Ecto.NoResultsError, queryable: Idejo.Accounts.User
    end
  end
end
