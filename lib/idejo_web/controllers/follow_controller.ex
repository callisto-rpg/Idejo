# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.FollowController do
  @moduledoc """
  Follow and unfollow a topic (TP-13): plain form posts from the topic page, so they work
  without JavaScript. Only a topic the user may view can be followed; any other is not found.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum
  alias Idejo.Reading

  def create(conn, %{"id" => id}) do
    with_topic(conn, id, fn user, topic ->
      :ok = Reading.follow(user, topic)
      {topic, gettext("You follow this topic.")}
    end)
  end

  def delete(conn, %{"id" => id}) do
    with_topic(conn, id, fn user, topic ->
      :ok = Reading.unfollow(user, topic)
      {topic, gettext("You no longer follow this topic.")}
    end)
  end

  defp with_topic(conn, id, fun) do
    user = conn.assigns.current_scope.user

    case Forum.get_viewable_topic(user, id) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

      topic ->
        {topic, message} = fun.(user, topic)

        conn
        |> put_flash(:info, message)
        |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
    end
  end
end
