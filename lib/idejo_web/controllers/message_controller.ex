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

    # A message the reader may not view is treated like its topic (steward decision,
    # 2026-10-24): sign-in, or home with a dialog.
    case Forum.get_viewable_message(user, id) do
      nil ->
        IdejoWeb.Unavailable.redirect_away(conn, :topic)

      %{topic: topic} = message ->
        redirect(conn, to: ~p"/t/#{topic.id}/#{topic.slug}" <> "#message-#{message.id}")
    end
  end
end
