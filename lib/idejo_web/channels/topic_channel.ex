# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicChannel do
  @moduledoc """
  A topic's (or a private conversation's) events for the official app (AP-15, AP-16;
  steward decision, 2026-11-10): `topic:<id>` and `conversation:<id>`.

  Joining needs the view right (`Forum.get_viewable_topic/2`; a conversation, its
  participants and the token's `private` scope); the reply carries the topic's change
  cursor. The channel subscribes to the same PubSub topic as `IdejoWeb.TopicLive`
  (`"topic:{id}"`) and turns each event into API objects for its member
  (`Idejo.Api`): `message.opened`, `.appended`, `.edited`, `.closed`, `.deleted`,
  `reaction.changed`, `poll.updated`, `topic.updated`, `topic.moved`, `topic.archived`,
  `messages.moved`, each with the change `cursor` where it has one. It checks the right
  again when the topic changes or the permission grid does (`Access.subscribe_permissions/0`,
  as `TopicLive` does): a member who lost it gets `forbidden` and is left.

  While joined, the member counts as viewing the topic (`Idejo.Messages.Authors`): no push
  about it (PN-08), and their open message stays open (GM-12) until they have been gone for
  the grace.

  The client may push `typing` (`{"typing": true}`), as the composer's typing endpoint.
  Typing is never broadcast: Idejo shows nobody that someone is typing.
  """
  use Phoenix.Channel

  alias Idejo.{Access, Api, Conversations, Forum, Messages}
  alias Idejo.Api.Changes
  alias Idejo.Messages.{Authors, Message}

  @impl true
  def join("topic:" <> id, _params, socket) do
    case Forum.get_viewable_topic(socket.assigns.user, id) do
      nil -> {:error, %{reason: "not_found"}}
      topic -> joined(socket, topic, :topic)
    end
  end

  def join("conversation:" <> id, _params, socket) do
    with true <- "private" in socket.assigns.token.scopes || {:error, :scope},
         %{} = topic <- Conversations.get(socket.assigns.user, id) || {:error, :not_found} do
      joined(socket, topic, :conversation)
    else
      {:error, :scope} -> {:error, %{reason: "insufficient_scope"}}
      {:error, :not_found} -> {:error, %{reason: "not_found"}}
    end
  end

  defp joined(socket, topic, kind) do
    :ok = Messages.subscribe(topic.id)
    if kind == :topic, do: :ok = Access.subscribe_permissions()
    # PN-08 and GM-12: this member is viewing the topic, as an open topic page would.
    :ok = Authors.present(topic.id, socket.assigns.user.id)

    socket =
      socket
      |> assign(:topic, topic)
      |> assign(:kind, kind)
      |> assign(:joined_at, DateTime.utc_now())
      |> assign(:seen, %{})

    {:ok, %{"cursor" => Changes.cursor(topic)}, socket}
  end

  @impl true
  def handle_in("typing", params, socket) do
    typing? = params["typing"] != false

    case Messages.typing(socket.assigns.user, socket.assigns.topic, typing?) do
      {:ok, _at} -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in(_event, _params, socket),
    do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

  @impl true
  def handle_info({:message, %Message{} = message}, socket) do
    user = socket.assigns.user
    event = event(message, socket.assigns.seen[message.id], socket.assigns.joined_at)

    push(socket, event, %{"message" => Api.message(user, message), "cursor" => message.change_seq})

    seen = Map.put(socket.assigns.seen, message.id, {message.state, message.body_md})
    {:noreply, assign(socket, :seen, seen)}
  end

  def handle_info({:reactions, message_id, summary}, socket) do
    push(socket, "reaction.changed", %{
      "message_id" => message_id,
      "reactions" => Api.reactions(summary, socket.assigns.user)
    })

    {:noreply, socket}
  end

  def handle_info({:poll, message_id, summary}, socket) do
    case Forum.get_readable_message(socket.assigns.user, message_id) do
      nil ->
        :ok

      message ->
        push(socket, "poll.updated", %{
          "message_id" => message_id,
          "poll" => Api.poll(summary, message, socket.assigns.user)
        })
    end

    {:noreply, socket}
  end

  def handle_info({:topic_changed, _id}, socket), do: recheck(socket)
  def handle_info({:topic_icon, _icon}, socket), do: recheck(socket)
  def handle_info(:permissions_changed, socket), do: recheck(socket)

  def handle_info({:messages_moved, id}, socket) do
    push(socket, "messages.moved", %{"topic_id" => id})
    {:noreply, socket}
  end

  def handle_info({:forked, message_id}, socket) do
    case Forum.get_readable_message(socket.assigns.user, message_id) do
      nil ->
        :ok

      message ->
        push(socket, "message.forked", %{"message" => Api.message(socket.assigns.user, message)})
    end

    {:noreply, socket}
  end

  # Timers, scheduled messages and anything else of the web page's: nothing for the app.
  def handle_info(_event, socket), do: {:noreply, socket}

  # Which event a message's change is, from what this member saw of it.
  defp event(%Message{deleted_at: %DateTime{}}, _seen, _joined_at), do: "message.deleted"

  defp event(message, nil, joined_at) do
    cond do
      not DateTime.before?(message.opened_at, joined_at) ->
        "message.opened"

      (message.state == "closed" and message.closed_at) &&
          not DateTime.before?(message.closed_at, joined_at) ->
        "message.closed"

      message.state == "open" ->
        "message.appended"

      true ->
        "message.edited"
    end
  end

  defp event(%Message{state: "closed"}, {"open", _body}, _joined_at), do: "message.closed"

  defp event(%Message{state: "open", body_md: body}, {"open", before}, _joined_at),
    do:
      if(String.starts_with?(body || "", before || ""),
        do: "message.appended",
        else: "message.edited"
      )

  defp event(_message, _seen, _joined_at), do: "message.edited"

  # The topic changed, or the grid did: still viewable? Then what changed.
  defp recheck(socket) do
    %{user: user, topic: before, kind: kind} = socket.assigns

    topic =
      case kind do
        :topic -> Forum.get_viewable_topic(user, before.id)
        :conversation -> Conversations.get(user, before.id)
      end

    case topic do
      nil ->
        push(socket, "forbidden", %{"reason" => "forbidden"})
        {:stop, :normal, socket}

      topic ->
        push(socket, topic_event(before, topic), Api.topic(user, topic))
        {:noreply, assign(socket, :topic, topic)}
    end
  end

  defp topic_event(%{state: state}, %{state: "archived"}) when state != "archived",
    do: "topic.archived"

  defp topic_event(%{category_id: id}, %{category_id: other}) when id != other, do: "topic.moved"
  defp topic_event(_before, _topic), do: "topic.updated"
end
