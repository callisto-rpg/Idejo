# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CategoryChannel do
  @moduledoc """
  A category's topic events for the official app (AP-15): `category:<id>`. Joining needs the
  view right. Events: `topic.created` (the topic), `topic.activity` (a new message: its
  last activity and count), `topic.moved` (in or out), `topic.archived`. A member who
  loses the view right gets `forbidden` and is left.
  """
  use Phoenix.Channel

  alias Idejo.{Access, Api, Forum}

  @impl true
  def join("category:" <> id, _params, socket) do
    if viewable?(socket.assigns.user, id) do
      :ok = Forum.subscribe_category(id)
      :ok = Access.subscribe_permissions()
      {:ok, assign(socket, :category_id, id)}
    else
      {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_info({:topic_created, topic_id}, socket) do
    with_topic(
      socket,
      topic_id,
      &push(socket, "topic.created", Api.topic(socket.assigns.user, &1))
    )
  end

  def handle_info({:topic_activity, topic_id}, socket) do
    with_topic(socket, topic_id, fn topic ->
      push(socket, "topic.activity", %{
        "topic_id" => topic.id,
        "last_activity_at" => Api.time(topic.last_activity_at),
        "messages_count" => topic.message_count
      })
    end)
  end

  def handle_info({:topic_moved, topic_id, from, to}, socket) do
    push(socket, "topic.moved", %{"topic_id" => topic_id, "from" => from, "to" => to})
    {:noreply, socket}
  end

  def handle_info({:topic_archived, topic_id}, socket) do
    push(socket, "topic.archived", %{"topic_id" => topic_id})
    {:noreply, socket}
  end

  def handle_info(:permissions_changed, socket) do
    if viewable?(socket.assigns.user, socket.assigns.category_id) do
      {:noreply, socket}
    else
      push(socket, "forbidden", %{"reason" => "forbidden"})
      {:stop, :normal, socket}
    end
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp with_topic(socket, topic_id, fun) do
    case Forum.get_viewable_topic(socket.assigns.user, topic_id) do
      nil -> :ok
      topic -> fun.(topic)
    end

    {:noreply, socket}
  end

  defp viewable?(user, id),
    do: Enum.any?(Forum.list_viewable_categories(user), &(&1.id == id))
end
