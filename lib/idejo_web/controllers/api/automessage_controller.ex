# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AutomessageController do
  @moduledoc """
  Automessages (AP-12, AP-13): the `!commands` a user may post in a topic (every one for its
  moderators, the `everyone` ones for others who may post), and posting one.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Messages.Automessages

  def index(conn, params) do
    with {:ok, topic} <- readable_topic(conn, params["topic_id"]) do
      commands =
        for %{name: name, sender: sender} <- Automessages.commands_for(user(conn), topic),
            do: %{"name" => name, "sender" => sender}

      send_list(conn, commands)
    end
  end

  def create(conn, %{"id" => id, "name" => name}) do
    with {:ok, topic} <- readable_topic(conn, id),
         {:ok, message} <- Automessages.post(user(conn), topic, name) do
      json(conn, Api.message(user(conn), message))
    end
  end
end
