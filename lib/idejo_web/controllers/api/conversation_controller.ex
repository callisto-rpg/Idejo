# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.ConversationController do
  @moduledoc """
  Private conversations (steward decision, 2026-10-27; AP-12), scope `private`: the list,
  starting one (refused when the other person takes no private messages), one
  conversation, its messages and changes, and its composer, which has no slow mode. Only
  participants ever get one (`Idejo.Conversations.get/2`); search, categories and Unread
  never include them.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.{Conversations, Forum}
  alias IdejoWeb.Api.{ComposerController, TopicController}

  def index(conn, _params) do
    send_list(conn, Enum.map(Conversations.list(user(conn)), &card(conn, &1)))
  end

  def create(conn, params) do
    with {:ok, topic} <- Conversations.start(user(conn), string(params, "user_id") || ""),
         do: show_topic(conn, topic)
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
