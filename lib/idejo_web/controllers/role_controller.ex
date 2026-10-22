# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.RoleController do
  @moduledoc """
  A role's page, `/r/{slug}`, which a `+role` mention links to (TP-10; steward decision,
  2026-10-22): its name, colour and members. Public and server-rendered, like the user card:
  the roles of each user are shown on their card anyway. Member and guest have no page.
  """
  use IdejoWeb, :controller

  alias Idejo.Access

  def show(conn, %{"slug" => slug}) do
    case Access.get_role_by_slug(slug) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Access.Role

      role ->
        {members, count} = Access.list_role_members(role)

        render(conn, :show,
          role: role,
          members: members,
          count: count,
          page_title: IdejoWeb.Admin.role_name(role)
        )
    end
  end
end
