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

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Reading

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with %{} = topic <- Forum.get_viewable_topic(user, id),
         true <- Access.can?(user, :moderate, topic.category) do
      json(conn, %{
        following: Reading.follower_count(topic),
        inactive: Reading.inactive?(topic),
        inactive_allowed: Idejo.Settings.get(:inactive_topics),
        category_id: topic.category_id,
        archived: topic.state == "archived",
        unarchive_to: unarchive_to(user, topic)
      })
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  # Where it goes back to, when the moderator moderates that category too; else they pick
  # one of theirs.
  defp unarchive_to(user, topic) do
    case Forum.unarchive_target(topic) do
      nil ->
        nil

      category ->
        if Access.can?(user, :moderate, category),
          do: %{id: category.id, name: category.name},
          else: nil
    end
  end
end
