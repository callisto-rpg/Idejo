# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicAutofollowController do
  @moduledoc """
  The topic page's "Followed by everyone" switch, for owners and administrators
  (`Idejo.Forum.set_autofollow/3`; steward decision, 2026-10-23). A plain form post, so it
  works without JavaScript; `autofollow=true` turns it on, anything else off.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    case Forum.get_viewable_topic(user, id) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

      topic ->
        conn
        |> put_flash_for(Forum.set_autofollow(user, topic, params["autofollow"] == "true"))
        |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
    end
  end

  defp put_flash_for(conn, {:ok, %{autofollow: true}}),
    do:
      put_flash(conn, :info, gettext("Everyone now follows this topic, unless they unfollow it."))

  defp put_flash_for(conn, {:ok, _topic}),
    do: put_flash(conn, :info, gettext("This topic is no longer followed by everyone."))

  defp put_flash_for(conn, {:error, _}),
    do: put_flash(conn, :error, gettext("Only administrators can change this."))
end
