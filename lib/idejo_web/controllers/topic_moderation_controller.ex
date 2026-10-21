# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicModerationController do
  @moduledoc """
  The topic page's moderator form (TP-14): lock, unlock, pin or unpin, with an optional
  reason for the moderation log (MO-03). A plain form post, so it works without JavaScript.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  @actions %{"lock" => :lock, "unlock" => :unlock, "pin" => :pin, "unpin" => :unpin}

  def create(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with %{} = topic <- Forum.get_viewable_topic(user, id),
         {:ok, action} <- Map.fetch(@actions, params["action"]) do
      conn
      |> put_flash_for(Forum.moderate_topic(user, topic, action, params["reason"]), action)
      |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
    else
      _ -> raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic
    end
  end

  defp put_flash_for(conn, {:ok, _topic}, action), do: put_flash(conn, :info, done(action))

  defp put_flash_for(conn, {:error, :archived}, _action),
    do: put_flash(conn, :error, gettext("Archived topics are neither locked nor unlocked."))

  defp put_flash_for(conn, {:error, _}, _action),
    do: put_flash(conn, :error, gettext("You cannot moderate this topic."))

  defp done(:lock), do: gettext("Topic locked.")
  defp done(:unlock), do: gettext("Topic unlocked.")
  defp done(:pin), do: gettext("Topic pinned.")
  defp done(:unpin), do: gettext("Topic unpinned.")
end
