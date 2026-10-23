# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicController do
  @moduledoc """
  The public topic page at `/t/{id}/{slug}` (TP-01), server-rendered so it reads without
  JavaScript (AX-04, CL-02). `/t/{id}`, the topic's URI (FD-01), and any other slug redirect
  to it, so the URI and old links keep working after a rename.

  The messages, live (TP-04), and the message form come from `IdejoWeb.TopicLive`, embedded
  here; its first render is part of this page's HTML. Opening it marks the topic read for a
  signed-in user (TP-07); the oldest message unread before that is passed on, so the page
  opens there. `?reply_to={message id}` opens the form as a reply to that message (TP-08),
  without JavaScript needed to choose it.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum
  alias Idejo.Forum.Tags
  alias Idejo.Reading

  def show(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    # A topic in a category the visitor may not view is not found, like the category.
    case Forum.get_viewable_topic(user, id) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

      topic ->
        if params["slug"] == topic.slug do
          # Where the user left off, before opening the topic marks everything read (TP-07).
          first_unread = Reading.first_unread(user, topic)
          Reading.mark_read(user, topic)

          render(
            conn,
            :show,
            [
              topic: topic,
              page_title: topic.title,
              reply_to_id: params["reply_to"],
              first_unread: first_unread,
              following?: Reading.following?(user, topic),
              can_autofollow?: Idejo.Access.administrator?(user),
              can_rename?: Forum.can_rename_topic?(user, topic),
              forked_from: forked_from(user, topic),
              # Without ?reply_to=, which only opens the form.
              canonical_url: url(~p"/t/#{topic.id}/#{topic.slug}")
            ] ++ moderator_tools(user, topic)
          )
        else
          conn
          |> put_status(:moved_permanently)
          |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
        end
    end
  end

  # TP-14, TP-15: the moderator form; TP-19: the "Edit tags" form, its own right
  # (moderators' by default).
  defp moderator_tools(nil, _topic),
    do: [can_moderate?: false, move_targets: [], can_tag?: false, available_tags: []]

  defp moderator_tools(user, topic) do
    can_moderate? = Idejo.Access.can?(user, :moderate, topic.category)
    can_tag? = topic.state != "archived" and Idejo.Access.can?(user, :tag, topic.category)

    [
      can_moderate?: can_moderate?,
      move_targets: if(can_moderate?, do: Forum.list_move_targets(user, topic), else: []),
      can_tag?: can_tag?,
      available_tags: if(can_tag?, do: Tags.available_tags(topic.category), else: [])
    ]
  end

  # TP-09: the message this topic was started from, when the viewer may see it.
  defp forked_from(_user, %{forked_from_message_id: nil}), do: nil

  # A source deleted by a moderator (MO-02) is not shown either.
  defp forked_from(user, topic) do
    case Forum.get_viewable_message(user, topic.forked_from_message_id) do
      %{deleted_at: nil} = message -> Idejo.Repo.preload(message, :author)
      _ -> nil
    end
  end
end
