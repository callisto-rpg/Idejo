# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.ConversationController do
  @moduledoc """
  Private conversations (steward decision, 2026-10-27; AP-12), scope `private`: the list,
  starting one (refused when the other person takes no private messages), one
  conversation, its messages and changes, and its composer, which has no slow mode. Only
  participants ever get one (`Idejo.Conversations.get/2`); search, categories and Unread
  never include them. Since 0.3.21 only a group's inbox starts them (`Conversations.hosted?/0`).
  """
  use IdejoWeb.Api.Controller

  alias Idejo.{Conversations, Forum, Inbox}
  alias IdejoWeb.Api.{ComposerController, TopicController}

  def index(conn, _params) do
    send_list(conn, Enum.map(Conversations.list(user(conn)), &card(conn, &1)))
  end

  # Only the group's inbox hosts them (steward decision, 2026-11-20): elsewhere, not found.
  def create(conn, params) do
    with true <- Conversations.hosted?() || {:error, :not_found},
         {:ok, recipient} <- recipient(params),
         {:ok, topic} <- Conversations.start(user(conn), recipient),
         do: show_topic(conn, topic)
  end

  # A group's inbox also takes the other person's idejo ID (`subject`), as the web's
  # `/chat/new?with=` (steward request, 2026-11-19): the account linked to it, made from the
  # provider's profile when there is none (`Inbox.member/1`). Unknown: refused as an
  # unknown id.
  defp recipient(params) do
    case string(params, "subject") do
      subject when is_binary(subject) and subject != "" -> member(subject)
      _ -> {:ok, string(params, "user_id") || ""}
    end
  end

  defp member(subject) do
    with true <- Inbox.on?(),
         {:ok, user} <- Inbox.member(subject) do
      {:ok, user}
    else
      _ -> {:error, :forbidden}
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, topic} <- conversation(conn, id), do: show_topic(conn, topic)
  end

  def messages(conn, %{"id" => id} = params) do
    with {:ok, topic} <- conversation(conn, id), do: TopicController.window(conn, topic, params)
  end

  def changes(conn, %{"id" => id} = params) do
    with {:ok, topic} <- conversation(conn, id),
         do: TopicController.changes_of(conn, topic, params)
  end

  def composer(conn, %{"id" => id}) do
    with {:ok, topic} <- conversation(conn, id),
         do: json(conn, ComposerController.composer(conn, topic))
  end

  def typing(conn, %{"id" => id} = params) do
    with {:ok, topic} <- conversation(conn, id),
         do: ComposerController.typing_in(conn, topic, params)
  end

  def commit(conn, %{"id" => id} = params) do
    with {:ok, topic} <- conversation(conn, id),
         do: ComposerController.commit_in(conn, topic, params)
  end

  defp conversation(conn, id) when is_binary(id) do
    case Conversations.get(user(conn), id) do
      nil -> {:error, :not_found}
      topic -> {:ok, topic}
    end
  end

  defp conversation(_conn, _id), do: {:error, :not_found}

  defp show_topic(conn, topic) do
    card =
      Enum.find(Conversations.list(user(conn)), &(&1.topic.id == topic.id)) ||
        %{topic: topic, others: Conversations.others(topic, user(conn)), last: nil, unread: 0}

    json(conn, card(conn, card))
  end

  defp card(_conn, %{topic: topic, others: others, last: last, unread: unread}) do
    %{
      "id" => topic.id,
      "uri" => topic.uri,
      "url" => Api.base() <> "/p/" <> topic.id,
      "with" => Enum.map(others, &Api.person/1),
      "unread_count" => unread,
      "last_message" =>
        last &&
          %{
            "id" => last.id,
            "author_name" => Idejo.Messages.author_name(last),
            "excerpt" => Forum.excerpt(last),
            "opened_at" => Api.time(last.opened_at)
          },
      "created_at" => Api.time(topic.created_at),
      "last_activity_at" => Api.time(topic.last_activity_at)
    }
  end
end
