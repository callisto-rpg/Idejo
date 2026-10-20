# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CategoryHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.CategoryController`.
  """
  use IdejoWeb, :html

  embed_templates "category_html/*"

  @doc """
  The unread marker of a topic in a list (TP-03, TP-07): how many messages are new to the
  user, a growing message counting once. Nothing when there are none.
  """
  attr :count, :integer, default: nil

  def unread_marker(assigns) do
    ~H"""
    <span :if={@count} class="badge badge-sm badge-primary ml-1 unread-marker">
      {ngettext("1 new", "%{count} new", @count)}
    </span>
    """
  end
end
