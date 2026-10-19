# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PageController do
  use IdejoWeb, :controller

  alias Idejo.Forum

  @doc """
  The home page: the categories the visitor or user may view (AC-05), in their order.
  """
  def home(conn, _params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    render(conn, :home,
      categories: Forum.list_viewable_categories(user),
      canonical_url: url(~p"/")
    )
  end
end
