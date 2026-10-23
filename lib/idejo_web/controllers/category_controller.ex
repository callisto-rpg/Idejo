# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CategoryController do
  @moduledoc """
  The public category page at `/c/{slug}` (AC-05), server-rendered so it works without
  JavaScript (AX-04, CL-02): its topics, pinned first, then the most recently active (TP-03),
  with the signed-in user's unread count (TP-07), and a “New topic” button for those who may
  start one (TP-01).
  """
  use IdejoWeb, :controller

  alias Idejo.Forum
  alias Idejo.Reading

  def show(conn, %{"slug" => slug} = params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    # A category the visitor may not view is not found, so its name is not given away.
    case Forum.get_viewable_category(user, slug) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Category

      category ->
        page = page(params)
        {topics, more?} = Forum.list_topics(category, page: page)
        # Compact or expanded topic cards (steward decision, 2026-10-23).
        {conn, view} = IdejoWeb.TopicView.choose(conn, params)

        render(conn, :show,
          category: category,
          page_title: category.name,
          can_start?: Forum.can_start_topic?(user, category),
          topics: topics,
          unread: Reading.unread_counts(user, Enum.map(topics, & &1.id)),
          page: page,
          more?: more?,
          view: view,
          previews: IdejoWeb.TopicView.previews(view, topics),
          canonical_url: canonical_url(category, page)
        )
    end
  end

  # Each page of the list is its own address; the first has no ?page=.
  defp canonical_url(category, 1), do: url(~p"/c/#{category.slug}")
  defp canonical_url(category, page), do: url(~p"/c/#{category.slug}?page=#{page}")

  defp page(%{"page" => page}) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page(_params), do: 1
end
