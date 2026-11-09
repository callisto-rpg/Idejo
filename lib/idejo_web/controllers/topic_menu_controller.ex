# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicMenuController do
  @moduledoc """
  What the moderators' part of the topic menu needs about one topic (steward decisions,
  2026-11-01), asked by `assets/js/topic_menu.js` when the menu opens: how many follow it,
  whether it is inactive, its category (left out of "Move to") and its state, and for an
  archived topic the category it goes back to (`Forum.unarchive_target/1`, or nil: pick
  one). Owners and administrators only; others get 404.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  # `Forum.topic_menu/2` checks the moderate right.
  def show(conn, %{"id" => id}) do
    case Forum.topic_menu(conn.assigns.current_scope.user, id) do
      {:ok, menu} -> json(conn, menu)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end
end
