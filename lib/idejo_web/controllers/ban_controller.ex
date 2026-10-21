# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.BanController do
  @moduledoc """
  Bans (MO-02) from the "User actions" of the user card, on its page `/u/{id}` or in a
  topic's dialog: server moderators ban an account for a number of days or for good, or lift
  a ban, with an optional reason for the moderation log. A banned account's sessions are
  disconnected at once. Plain form posts; from a topic, `return_to` leads back to it.
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
      conn |> put_flash(:info, gettext("Account banned.")) |> redirect(to: back(params, user))
    else
      _ ->
        conn
        |> put_flash(:error, gettext("This account cannot be banned."))
        |> redirect(to: back(params, user))
    end
  end

  def delete(conn, %{"id" => id} = params) do
    user = user!(id)

    case Accounts.unban_user(conn.assigns.current_scope.user, user, params["reason"]) do
      {:ok, _} ->
        conn |> put_flash(:info, gettext("Ban lifted.")) |> redirect(to: back(params, user))

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("This ban could not be lifted."))
        |> redirect(to: back(params, user))
    end
  end

  # Back to the topic the card was opened in, or to the card's page. Only a topic's path is
  # followed, so the parameter can never send anyone to another site.
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

  # Only the offered choices: anything else bans nobody.
  defp until("forever"), do: {:ok, nil}

  defp until(days) when days in @days,
    do: {:ok, DateTime.add(DateTime.utc_now(), String.to_integer(days) * 86_400, :second)}

  defp until(_other), do: :error
end
