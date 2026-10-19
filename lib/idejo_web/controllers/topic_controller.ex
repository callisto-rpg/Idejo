# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicController do
  @moduledoc """
  The public topic page at `/t/{id}/{slug}` (TP-01), server-rendered so it reads without
  JavaScript (AX-04, CL-02). `/t/{id}`, the topic's URI (FD-01), and any other slug redirect
  to it, so the URI and old links keep working after a rename.

  The messages, live (TP-04), and the message form come from `IdejoWeb.TopicLive`, embedded
  here; its first render is part of this page's HTML. `?reply_to={message id}` opens the form
  as a reply to that message (TP-08), without JavaScript needed to choose it.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  def show(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    # A topic in a category the visitor may not view is not found, like the category.
    case Forum.get_viewable_topic(user, id) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

      topic ->
        if params["slug"] == topic.slug do
          render(conn, :show,
            topic: topic,
            page_title: topic.title,
            reply_to_id: params["reply_to"],
            # Without ?reply_to=, which only opens the form.
            canonical_url: url(~p"/t/#{topic.id}/#{topic.slug}")
          )
        else
          conn
          |> put_status(:moved_permanently)
          |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
        end
    end
  end
end
