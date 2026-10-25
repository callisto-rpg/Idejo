# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.FollowController do
  @moduledoc """
  Follow and unfollow a topic (TP-13): plain form posts from the topic page and the sidebar,
  so they work without JavaScript. Only a topic the user may view can be followed; any other
  is not found. The topic page leads back to the topic; the sidebar's "×" and "+"
  (`return=back`) to the page they were sent from, when the browser says which one.

  The topic menu (steward decision, 2026-10-23; right click or long press on a topic) posts
  here too, with `return=back`: unfollow, "Unfollow & mute" (`mute`) and "Mark unread"
  (`unread`).
  """
  use IdejoWeb, :controller

  alias Idejo.Forum
  alias Idejo.Reading

  def create(conn, %{"id" => id} = params) do
    with_topic(conn, id, params, fn user, topic ->
      :ok = Reading.follow(user, topic)
      {topic, gettext("You follow this topic.")}
    end)
  end

  def delete(conn, %{"id" => id} = params) do
    with_topic(conn, id, params, fn user, topic ->
      :ok = Reading.unfollow(user, topic)
      {topic, gettext("You no longer follow this topic.")}
    end)
  end

  def mute(conn, %{"id" => id} = params) do
    with_topic(conn, id, params, fn user, topic ->
      :ok = Reading.mute(user, topic)
      {topic, gettext("You no longer follow this topic, and it is muted.")}
    end)
  end

  def unread(conn, %{"id" => id} = params) do
    with_topic(conn, id, params, fn user, topic ->
      :ok = Reading.mark_unread(user, topic)
      {topic, gettext("Marked unread.")}
    end)
  end

  defp with_topic(conn, id, params, fun) do
    user = conn.assigns.current_scope.user

    case Forum.get_viewable_topic(user, id) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

      topic ->
        {topic, message} = fun.(user, topic)

        conn
        |> flash(params, message)
        |> redirect(to: back(conn, params) || ~p"/t/#{topic.id}/#{topic.slug}")
    end
  end

  # The sidebar's delayed unfollow (`quiet=1`, assets/js/sidebar.js) is sent from a page that
  # already said so: no message waits for the next one.
  defp flash(conn, %{"quiet" => "1"}, _message), do: conn
  defp flash(conn, _params, message), do: put_flash(conn, :info, message)

  # The referring page on this server, as a local path, or nil.
  defp back(conn, %{"return" => "back"}) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: "/" <> _ = path} = uri when host == conn.host <-
           URI.parse(referer),
         false <- String.starts_with?(path, ["//", "/\\"]) do
      if uri.query, do: path <> "?" <> uri.query, else: path
    else
      _ -> nil
    end
  end

  defp back(_conn, _params), do: nil
end
