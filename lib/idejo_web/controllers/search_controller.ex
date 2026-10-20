# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SearchController do
  @moduledoc """
  The Search screen (MVP §5, SE-01) at `/search`: a query box, a category filter and results
  with excerpts, 20 a page. Public and server-rendered (a GET form), so it works without
  JavaScript; visitors find what they may view (SE-02).
  """
  use IdejoWeb, :controller

  alias Idejo.Forum
  alias Idejo.Search

  def index(conn, params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user
    q = params["q"] || ""
    categories = Forum.list_viewable_categories(user)
    category = Enum.find(categories, &(&1.slug == params["category"]))
    page = page(params)
    {results, more?} = Search.search(user, q, category: category, page: page)

    render(conn, :index,
      page_title: gettext("Search"),
      q: q,
      categories: categories,
      category: category,
      results: results,
      page: page,
      more?: more?
    )
  end

  defp page(%{"page" => page}) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page(_params), do: 1
end
