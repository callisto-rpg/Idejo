# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TagController do
  @moduledoc """
  "Filter by tag" (TP-19) at `/tags`, public and server-rendered (a GET form, no JavaScript
  needed): the tags the visitor may filter by, grouped server-wide then by category, and the
  topics carrying every chosen tag (`?tags[]=slug`), or with `?op=or` at least one of them
  (the "Operator" toggle; steward decision, 2026-10-24), most recently active first, 30 a
  page. A tag's link elsewhere opens this page with it chosen.
  Unknown slugs and tags of categories the visitor may not view are ignored.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum.Tags

  def index(conn, params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user
    tags = Tags.list_viewable_tags(user)
    slugs = params |> Map.get("tags", []) |> List.wrap() |> Enum.filter(&is_binary/1)
    selected = Enum.filter(tags, &(&1.slug in slugs))
    page = page(params)
    op = if params["op"] == "or", do: :or, else: :and
    match = if op == :or, do: :any, else: :all
    {topics, more?} = Tags.list_tagged_topics(user, selected, page: page, match: match)
    topics = Idejo.Reading.put_inactive(topics)

    render(conn, :index,
      page_title: gettext("Filter by tag"),
      groups: groups(tags),
      selected: selected,
      op: op,
      topics: topics,
      page: page,
      more?: more?
    )
  end

  # Server-wide tags first, then each category's, in the categories' order.
  defp groups(tags) do
    tags
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn
      {nil, _} -> -1
      {category, _} -> category.position
    end)
  end

  defp page(%{"page" => page}) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page(_params), do: 1
end
