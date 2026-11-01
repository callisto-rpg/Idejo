# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicMenuController do
  @moduledoc """
  What the administrators' part of the topic menu needs about one topic (steward decision,
  2026-11-01), asked by `assets/js/topic_menu.js` when the menu opens: how many follow it,
  whether it is inactive, its category (left out of "Move to") and its state. Owners and
  administrators only; others get 404.
  """
  use IdejoWeb, :controller

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Reading

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with true <- Access.administrator?(user),
         %{} = topic <- Forum.get_viewable_topic(user, id) do
      json(conn, %{
        following: Reading.follower_count(topic),
        inactive: Reading.inactive?(topic),
        inactive_allowed: Idejo.Settings.get(:inactive_topics),
        category_id: topic.category_id,
        archived: topic.state == "archived"
      })
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end
end
