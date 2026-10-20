# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UnreadController do
  @moduledoc """
  “New since last visit” across categories (TP-07), at `/unread` for signed-in users: the
  topics with unread messages in every category they may view, most recently active first,
  30 a page (`?page=`).
  """
  use IdejoWeb, :controller

  alias Idejo.Reading

  def index(conn, params) do
    page = page(params)
    {rows, more?} = Reading.list_unread_topics(conn.assigns.current_scope.user, page: page)
    render(conn, :index, page_title: gettext("Unread"), rows: rows, page: page, more?: more?)
  end

  defp page(%{"page" => page}) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page(_params), do: 1
end
