# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MessageController do
  @moduledoc """
  Message permalinks (TP-06): `/m/{id}`, the message's URI (FD-01), leads to the message on
  its topic's page. It never changes, while the topic's address may (a rename changes the
  slug, a move changes nothing here), so the redirect is temporary (302).
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    # A message in a category the visitor may not view is not found, like its topic.
    case Forum.get_viewable_message(user, id) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Messages.Message

      %{topic: topic} = message ->
        redirect(conn, to: ~p"/t/#{topic.id}/#{topic.slug}" <> "#message-#{message.id}")
    end
  end
end
