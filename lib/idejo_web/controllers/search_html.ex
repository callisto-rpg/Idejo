# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SearchHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.SearchController`.
  """
  use IdejoWeb, :html

  embed_templates "search_html/*"

  @doc "The address of another page of the same search."
  def page_path(q, category, page) do
    params =
      [q: q, category: category && category.slug, page: page] |> Enum.reject(&is_nil(elem(&1, 1)))

    ~p"/search?#{params}"
  end
end
