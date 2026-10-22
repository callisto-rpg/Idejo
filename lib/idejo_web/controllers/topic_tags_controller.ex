# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicTagsController do
  @moduledoc """
  The topic page's "Edit tags" form (TP-19), for users with the `:tag` right in the topic's
  category (built-in moderators by default), with an optional reason for the moderation log
  (MO-03). A plain form post, so it works without JavaScript.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    case Forum.get_viewable_topic(user, id) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

      topic ->
        tag_ids = params |> Map.get("tag_ids", []) |> List.wrap() |> Enum.filter(&is_binary/1)

        conn
        |> put_flash_for(Forum.set_topic_tags(user, topic, tag_ids, params["reason"]))
        |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
    end
  end

  defp put_flash_for(conn, {:ok, _topic}), do: put_flash(conn, :info, gettext("Tags saved."))

  defp put_flash_for(conn, {:error, :tag_required}),
    do: put_flash(conn, :error, gettext("Choose at least one tag."))

  defp put_flash_for(conn, {:error, :archived}),
    do: put_flash(conn, :error, gettext("Archived topics keep their tags."))

  defp put_flash_for(conn, {:error, _}),
    do: put_flash(conn, :error, gettext("You cannot change the tags of this topic."))
end
