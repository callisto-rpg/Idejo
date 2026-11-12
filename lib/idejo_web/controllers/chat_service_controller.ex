# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ChatServiceController do
  @moduledoc """
  The chat service's questions (steward request, 2026-11-10; `Idejo.Community.Chat`), JSON,
  no session: the `ticket` the service made for one member is the authority, checked with
  the service itself (`Chat.check_ticket/2`). Without a chat service, or for a ticket it does
  not vouch for, 404, so nothing tells a stranger whether the address exists.

    * `GET /community/topics?ticket=`: the topics the member follows, as the expanded topic
      list shows them (`{"topics": [...]}`; addresses absolute);
    * `GET /community/conversations?ticket=`: their private conversations to copy
      (`{"conversations": [...], "remaining"}`);
    * `POST /community/conversations/moved` `{"ticket", "ids"}`: those the service copied,
      which the forum then no longer shows (`{"moved": n}`).
  """
  use IdejoWeb, :controller

  alias Idejo.Community.{Chat, ChatExport}
  alias Idejo.{Emoji, Forum, Messages, Uploads}
  alias Idejo.Forum.TopicIcons

  def topics(conn, params) do
    with true <- Chat.url() != nil,
         {:ok, user} <- Chat.check_ticket(params["ticket"], "topics") do
      topics = ChatExport.followed_topics(user)
      no_store(conn) |> json(%{topics: Enum.map(topics, &topic_json/1)})
    else
      _ -> not_found(conn)
    end
  end

  def conversations(conn, params) do
    with true <- Chat.url() != nil,
         {:ok, user} <- Chat.check_ticket(params["ticket"], "conversations") do
      %{conversations: list, remaining: remaining} = ChatExport.conversations(user)

      no_store(conn)
      |> json(%{
        conversations: Enum.map(list, &conversation_json/1),
        remaining: remaining,
        url: absolute_url("/p")
      })
    else
      _ -> not_found(conn)
    end
  end

  def moved(conn, params) do
    with true <- Chat.url() != nil,
         ids when is_list(ids) <- params["ids"],
         {:ok, user} <- Chat.check_ticket(params["ticket"], "conversations") do
      {:ok, count} = ChatExport.moved(user, ids)
      Chat.forget(user.id)
      json(conn, %{moved: count})
    else
      _ -> not_found(conn)
    end
  end

  defp topic_json(%{topic: topic, unread: unread, preview: preview} = entry) do
    preview =
      preview || %{first: nil, latest: [], images: [], participants: [], participant_count: 0}

    %{
      id: topic.id,
      title: topic.title,
      url: absolute_url("/t/#{topic.id}/#{topic.slug}"),
      unread: unread,
      # The inbox's topic cards (steward request, 2026-11-12): unread @/+ mentions, and
      # others' reactions to the member's messages since they last read the topic.
      mentions: Map.get(entry, :mentions, 0),
      reactions: Map.get(entry, :reactions, 0),
      message_count: topic.message_count,
      last_activity_at: topic.last_activity_at,
      pinned: topic.pinned,
      state: topic.state,
      category: category_json(topic.category),
      first: preview.first && Forum.excerpt(preview.first, 400),
      latest: Enum.map(preview.latest, &latest_json/1),
      people:
        for(
          user <- Enum.take(preview.participants, 6),
          do: %{name: user.display_name, avatar: avatar(user)}
        ),
      people_count: preview.participant_count,
      # The inbox draws Idejo's own topic row from these (steward request, 2026-11-10):
      # paths stay relative to this forum, the inbox prefixes them.
      slug: topic.slug,
      topical: topic.topical,
      icon_path: topic.topical && icon_path(topic),
      author: !topic.topical && user_json(topic.author),
      preview: %{
        first: message_json(preview.first),
        images: preview.images,
        latest: Enum.map(preview.latest, &message_json/1),
        participants: Enum.map(Enum.take(preview.participants, 6), &user_json/1),
        participant_count: preview.participant_count
      }
    }
  end

  # Loaded with the topic (`ChatExport.followed_topics/1`).
  defp icon_path(topic), do: TopicIcons.url(topic.icon)

  defp user_json(%Idejo.Accounts.User{} = user) do
    %{
      display_name: user.display_name,
      username: user.username,
      avatar_id: user.avatar_id,
      avatar_dark_id: user.avatar_dark_id,
      status: user.status
    }
  end

  defp user_json(_user), do: nil

  defp message_json(nil), do: nil

  defp message_json(m) do
    %{
      id: m.id,
      body_html: m.body_html,
      anonymous: m.anonymous,
      spoiler: m.spoiler,
      spoiler_label: m.spoiler_label,
      opened_at: m.opened_at,
      author: !m.anonymous && user_json(m.author)
    }
  end

  defp category_json(nil), do: nil

  defp category_json(category),
    do: %{
      id: category.id,
      name: category.name,
      slug: category.slug,
      icon: category.icon,
      url: absolute_url("/c/#{category.slug}"),
      colour: category.colour
    }

  defp latest_json(m) do
    %{
      author: Messages.author_name(m),
      avatar: !m.anonymous && avatar(m.author),
      text: Forum.excerpt(m, 160),
      url: absolute_url("/m/#{m.id}"),
      at: m.opened_at
    }
  end

  defp conversation_json(%{topic: topic, subjects: subjects, messages: messages}) do
    %{
      id: topic.id,
      subjects: subjects,
      messages:
        for %{message: m, author_subject: author, reactions: reactions} <- messages do
          %{
            id: m.id,
            author: author,
            body_md: m.body_md,
            body_html: absolute(m.body_html),
            opened_at: m.opened_at,
            edited: m.edited,
            reply_to: m.reply_to_id,
            spoiler: m.spoiler,
            reactions:
              for {name, subject} <- reactions do
                %{emoji: name, char: (Emoji.lookup(name) || %{})[:char], subject: subject}
              end
          }
        end
    }
  end

  defp avatar(user) do
    case Uploads.avatar_url(user) do
      nil -> nil
      path -> absolute_url(path)
    end
  end

  # Stored HTML links this server by path (`/u/…`, `/uploads/…`): the service shows it on
  # another host.
  defp absolute(nil), do: nil

  defp absolute(html),
    do: String.replace(html, ~r/(href|src)="\/(?!\/)/, "\\1=\"" <> IdejoWeb.Endpoint.url() <> "/")

  defp absolute_url(path), do: IdejoWeb.Endpoint.url() <> path

  defp no_store(conn), do: put_resp_header(conn, "cache-control", "no-store")

  defp not_found(conn), do: conn |> put_status(404) |> json(%{error: "not found"})
end
