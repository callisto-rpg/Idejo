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
  alias Idejo.Forum.TopicWindow
  alias Idejo.Reading

  def show(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    # A topic the reader may not view leads to sign-in, or home with a dialog
    # (steward decision, 2026-10-24).
    case Forum.get_readable_topic(user, id) do
      nil ->
        IdejoWeb.Unavailable.redirect_away(conn, :topic)

      # A private conversation's URI (FD-01) leads its participants to its page (steward
      # decision, 2026-10-27).
      %{private: true} = topic ->
        redirect(conn, to: ~p"/p/#{topic.id}")

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
              window: window(params),
              following?: Reading.following?(user, topic),
              can_autofollow?: Idejo.Access.administrator?(user),
              can_rename?: Forum.can_rename_topic?(user, topic),
              forked_from: forked_from(user, topic),
              # Without ?reply_to=, which only opens the form, or ?around=; a page, its own.
              canonical_url: canonical(topic, params),
              # PN-20: the notifications banner.
              push_banner?: Idejo.Push.banner?(user)
            ] ++ moderator_tools(user, topic)
          )
        else
          conn
          |> put_status(:moved_permanently)
          |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
        end
    end
  end

  # Long topics (steward decision, 2026-11-01): which messages the page opens with, a page
  # (`?page=n`) or around a message (`?around=`, from its permalink, TP-06); else where the
  # reader left off, or the end (IdejoWeb.TopicLive).
  @doc false
  def window(params), do: Map.take(params, ["page", "around"])

  # SE-04: each page of a long topic is its own, the first too, as the topic's own address
  # opens at its end, not on page 1. A page past the end shows the last; a topic of one page,
  # or a page that is not a number, is the topic's address.
  defp canonical(topic, %{"page" => page}) when is_binary(page) do
    with {n, ""} when n > 0 <- Integer.parse(page),
         pages when pages > 1 <- TopicWindow.pages(topic, TopicWindow.sizes().page) do
      url(~p"/t/#{topic.id}/#{topic.slug}?#{[page: min(n, pages)]}")
    else
      _ -> url(~p"/t/#{topic.id}/#{topic.slug}")
    end
  end

  defp canonical(topic, _params), do: url(~p"/t/#{topic.id}/#{topic.slug}")

  # TP-14, TP-15: the moderator form; TP-19: the "Edit tags" form, its own right
  # (moderators' by default).
  defp moderator_tools(nil, _topic),
    do: [
      can_moderate?: false,
      move_targets: [],
      unarchive_to: nil,
      can_tag?: false,
      available_tags: []
    ]

  defp moderator_tools(user, topic) do
    can_moderate? = Idejo.Access.can?(user, :moderate, topic.category)
    can_tag? = topic.state != "archived" and Idejo.Access.can?(user, :tag, topic.category)
    move_targets = if can_moderate?, do: Forum.list_move_targets(user, topic), else: []

    [
      can_moderate?: can_moderate?,
      move_targets: move_targets,
      # An archived topic goes back where it came from (steward decision, 2026-11-01), when
      # the moderator moderates it there; else they pick a category.
      unarchive_to: unarchive_to(topic, move_targets),
      can_tag?: can_tag?,
      available_tags: if(can_tag?, do: Tags.available_tags(topic.category), else: [])
    ]
  end

  defp unarchive_to(%{state: "archived"} = topic, [_ | _] = move_targets) do
    case Forum.unarchive_target(topic) do
      nil -> nil
      original -> Enum.find(move_targets, &(&1.id == original.id))
    end
  end

  defp unarchive_to(_topic, _move_targets), do: nil

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
