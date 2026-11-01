# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MessageController do
  @moduledoc """
  Message permalinks (TP-06): `/m/{id}`, the message's URI (FD-01), leads to the message on
  its topic's page. It never changes, while the topic's address may (a rename changes the
  slug, a move changes nothing here), so the redirect is temporary (302).

  `?unread`, on the links of notifications (bubbles and pushes), leads instead to the oldest
  message the reader has not read in that topic, where the page's "N unread messages" line
  is, so they read on from there; with nothing unread, or a topic never opened, to the
  message itself.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum
  alias Idejo.Reading

  def show(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    # A message the reader may not view is treated like its topic (steward decision,
    # 2026-10-24): sign-in, or home with a dialog.
    case Forum.get_readable_message(user, id) do
      nil ->
        IdejoWeb.Unavailable.redirect_away(conn, :topic)

      %{topic: topic} = message ->
        target = if Map.has_key?(params, "unread"), do: first_unread(user, topic), else: nil
        target = target || message.id
        redirect(conn, to: page(topic, target) <> "#message-#{target}")
    end
  end

  # Long topics load around the message (`?around=`, steward decision, 2026-11-01). Steward
  # decision, 2026-10-27: a private conversation's message, for a participant.
  defp page(%{private: true} = topic, id), do: ~p"/p/#{topic.id}?#{[around: id]}"
  defp page(topic, id), do: ~p"/t/#{topic.id}/#{topic.slug}?#{[around: id]}"

  defp first_unread(user, topic) do
    case Reading.first_unread(user, topic) do
      %{id: id} -> id
      nil -> nil
    end
  end
end
