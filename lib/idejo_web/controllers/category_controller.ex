# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CategoryController do
  @moduledoc """
  The public category page at `/c/{slug}` (AC-05), server-rendered so it works without
  JavaScript (AX-04, CL-02), with a “New topic” button for those who may start one (TP-01).
  Topics are listed here from TP-03.
  """
  use IdejoWeb, :controller

  alias Idejo.Access
  alias Idejo.Forum

  def show(conn, %{"slug" => slug}) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    # A category the visitor may not view is not found, so its name is not given away.
    case Forum.get_viewable_category(user, slug) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Category

      category ->
        render(conn, :show,
          category: category,
          page_title: category.name,
          can_start?: user != nil and Access.can?(user, :start, category)
        )
    end
  end
end
