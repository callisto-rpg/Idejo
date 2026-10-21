# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.BanController do
  @moduledoc """
  Bans (MO-02) from the user card page, `/u/{id}`: server moderators ban an account for a
  number of days or for good, or lift a ban, with an optional reason for the moderation log.
  A banned account's sessions are disconnected at once. Plain form posts.
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts
  alias IdejoWeb.UserAuth

  @days ~w(1 7 30 365)

  def create(conn, %{"id" => id} = params) do
    user = user!(id)

    with {:ok, until} <- until(params["days"]),
         {:ok, {_banned, socket_ids}} <-
           Accounts.ban_user(conn.assigns.current_scope.user, user, until, params["reason"]) do
      UserAuth.disconnect_sessions(socket_ids)
      conn |> put_flash(:info, gettext("Account banned.")) |> redirect(to: ~p"/u/#{user.id}")
    else
      _ ->
        conn
        |> put_flash(:error, gettext("This account cannot be banned."))
        |> redirect(to: ~p"/u/#{user.id}")
    end
  end

  def delete(conn, %{"id" => id} = params) do
    user = user!(id)

    case Accounts.unban_user(conn.assigns.current_scope.user, user, params["reason"]) do
      {:ok, _} ->
        conn |> put_flash(:info, gettext("Ban lifted.")) |> redirect(to: ~p"/u/#{user.id}")

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("This ban could not be lifted."))
        |> redirect(to: ~p"/u/#{user.id}")
    end
  end

  defp user!(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = user <- Accounts.get_user(id) do
      user
    else
      _ -> raise Ecto.NoResultsError, queryable: Idejo.Accounts.User
    end
  end

  # Only the offered choices: anything else bans nobody.
  defp until("forever"), do: {:ok, nil}

  defp until(days) when days in @days,
    do: {:ok, DateTime.add(DateTime.utc_now(), String.to_integer(days) * 86_400, :second)}

  defp until(_other), do: :error
end
