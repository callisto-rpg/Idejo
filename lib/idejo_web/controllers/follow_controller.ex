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

  alias Idejo.Reading

  def create(conn, %{"id" => id} = params),
    do: act(conn, :follow, id, params, gettext("You follow this topic."))

  def delete(conn, %{"id" => id} = params),
    do: act(conn, :unfollow, id, params, gettext("You no longer follow this topic."))

  def mute(conn, %{"id" => id} = params),
    do: act(conn, :mute, id, params, gettext("You no longer follow this topic, and it is muted."))

  def unread(conn, %{"id" => id} = params),
    do: act(conn, :mark_unread, id, params, gettext("Marked unread."))

  # `Reading.act_on_topic/3` checks the topic is one the user may view.
  defp act(conn, action, id, params, message) do
    case Reading.act_on_topic(conn.assigns.current_scope.user, action, id) do
      {:ok, topic} ->
        conn
        |> put_flash(:info, message)
        |> redirect(to: back(conn, params) || ~p"/t/#{topic.id}/#{topic.slug}")

      {:error, :not_found} ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic
    end
  end

  defp back(conn, params), do: IdejoWeb.ReturnBack.path(conn, params)
end
