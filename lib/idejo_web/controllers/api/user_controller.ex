# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.UserController do
  @moduledoc "User cards, role pages and ignoring (AC-06, TP-10, AP-12)."
  use IdejoWeb.Api.Controller

  alias Idejo.{Access, Accounts}

  def show(conn, %{"id" => id}) do
    with {:ok, user} <- visible_user(id), do: json(conn, Api.user_card(user(conn), user))
  end

  def ignore(conn, %{"id" => id}) do
    with {:ok, other} <- visible_user(id),
         {:ok, _} <- Accounts.ignore_user(user(conn), other) |> ok(),
         do: json(conn, Api.user_card(user(conn), other))
  end

  def unignore(conn, %{"id" => id}) do
    with {:ok, other} <- visible_user(id),
         {:ok, _} <- Accounts.unignore_user(user(conn), other) |> ok(),
         do: json(conn, Api.user_card(user(conn), other))
  end

  defp ok(:ok), do: {:ok, nil}
  defp ok({:error, reason}), do: {:error, reason}

  @doc "`/r/{slug}`: the role and its members, as the public role page shows them."
  def role(conn, %{"id" => slug}) do
    case Access.get_role_by_slug(slug) do
      nil ->
        {:error, :not_found}

      role ->
        {members, count} = Access.list_role_members(role)

        json(conn, %{
          "id" => role.id,
          "name" => role.name,
          "slug" => Access.role_slug(role),
          "colour" => role.colour,
          "members" => Enum.map(members, &Api.person/1),
          "members_count" => count
        })
    end
  end

  # Anyone with an account a card may show (`/u/{id}` is public): not server accounts' email,
  # never anyone's; deleted accounts show as "Deleted user".
  @doc false
  def visible_user(id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Accounts.User{} = user <- Accounts.get_user(uuid) do
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end

  def visible_user(_id), do: {:error, :not_found}
end
