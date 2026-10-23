# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UnreadController do
  @moduledoc """
  “New since last visit” across categories (TP-07), at `/unread` for signed-in users: the
  topics with unread messages in every category they may view, most recently active first.
  On the first page, "Following" lists every followed topic with something new (steward
  decision, 2026-10-23); "Other topics" lists the rest, 30 a page (`?page=`).
  """
  use IdejoWeb, :controller

  alias Idejo.Reading

  def index(conn, params) do
    page = page(params)
    user = conn.assigns.current_scope.user
    followed = if page == 1, do: Reading.list_unread_followed_topics(user), else: []
    {rows, more?} = Reading.list_unread_topics(user, page: page, following: false)

    render(conn, :index,
      page_title: gettext("Unread"),
      followed: followed,
      rows: rows,
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
