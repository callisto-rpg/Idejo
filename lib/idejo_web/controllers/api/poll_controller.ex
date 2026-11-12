# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.PollController do
  @moduledoc """
  Polls (`!poll`, AP-12): under the author's message (`message_id`), or on their own; votes,
  changed or taken back until the poll closes. Votes are anonymous.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Messages.{Message, Polls}

  @doc """
  `message_id` (or null), `question`, `options` (`[{"text", "emoji", "colour"}]`),
  `multiple`, `hours`, `hidden` (results hidden until it closes), `reply_to`.
  """
  def create(conn, %{"id" => id} = params) do
    attrs = %{
      "question" => params["question"],
      "options" => List.wrap(params["options"]),
      "multiple" => params["multiple"] == true,
      "hide_results" => params["hidden"] == true,
      "hours" =>
        if(is_number(params["hours"]), do: to_string(params["hours"]), else: params["hours"])
    }

    with {:ok, topic} <- readable_topic(conn, id),
         {:ok, message} <- poll(conn, topic, string(params, "message_id"), attrs, params) do
      json(conn, Api.message(user(conn), message))
    end
  end

  # On its own, or under the author's message of this topic.
  defp poll(conn, topic, nil, attrs, params) do
    with {:ok, message, _summary} <-
           Polls.post(user(conn), topic, attrs, string(params, "reply_to")),
         do: {:ok, message}
  end

  defp poll(conn, topic, message_id, attrs, _params) do
    with {:ok, message} <- readable_message(conn, message_id),
         true <- message.topic_id == topic.id || {:error, :not_found},
         {:ok, _summary} <- Polls.create(user(conn), message, attrs),
         do: {:ok, message}
  end

  def vote(conn, %{"id" => id} = params) do
    ids = params["option_ids"] |> List.wrap() |> Enum.filter(&is_binary/1)

    with %Message{} = message <-
           Polls.readable_message(user(conn), id) || {:error, :not_found},
         {:ok, _message} <- readable_message(conn, message.id),
         {:ok, summary} <- Polls.vote(user(conn), message, ids) do
      json(conn, Api.poll(summary, message, user(conn)))
    end
  end
end
