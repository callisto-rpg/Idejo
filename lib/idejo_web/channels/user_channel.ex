# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserChannel do
  @moduledoc """
  The signed-in user's own events for the official app (AP-15): `user:me`.

    * `notification`: the web's bubbles (a mention, a reply, a role mention, a new message
      in a followed topic, a reaction, a warning), from the same live notifications
      (`Idejo.Notifications.subscribe/1`), then `unread.changed` with the Unread counter;
    * `conversation.updated`: something new in one of their private conversations (scope
      `private`);
    * `scheduled.posted`: one of their scheduled messages went out;
    * `token.revoked`: this device was signed out (the socket closes right after);
    * `settings.changed`: settings that change how a client behaves.
  """
  use Phoenix.Channel

  alias Idejo.{Api, Conversations, Notifications, Reading, Settings}

  @client_settings ~w(server_name server_about server_rules gm_window_seconds gm_unanswered_minutes gm_early_reply gif_api_key upload_max_mb push_enabled api_enabled registration_mode)a

  @impl true
  def join("user:me", _params, socket) do
    user = socket.assigns.user
    :ok = Notifications.subscribe(user)
    :ok = Phoenix.PubSub.subscribe(Idejo.PubSub, "app_user:" <> user.id)
    :ok = Phoenix.PubSub.subscribe(Idejo.PubSub, "api_token:" <> socket.assigns.token.id)
    :ok = Settings.subscribe()
    {:ok, %{"unread" => counter(user)}, socket}
  end

  @impl true
  def handle_info({:notification, live}, socket) do
    user = socket.assigns.user

    push(socket, "notification", %{
      "kind" => live.kind,
      "message_id" => live.message_id,
      "topic_id" => live.topic_id,
      "topic_title" => live.topic_title,
      "author_name" => live.author_name,
      "excerpt" => live.excerpt,
      "emoji_url" => live.emoji && Api.absolute(live.emoji.src)
    })

    if "private" in socket.assigns.token.scopes and Conversations.get(user, live.topic_id),
      do: push(socket, "conversation.updated", %{"conversation_id" => live.topic_id})

    push(socket, "unread.changed", counter(user))
    {:noreply, socket}
  end

  def handle_info({:warning, warning}, socket) do
    push(socket, "notification", %{
      "kind" => "warning",
      "message_id" => warning.message_id,
      "reason" => warning.reason,
      "warning_id" => warning.id
    })

    {:noreply, socket}
  end

  def handle_info({:scheduled_posted, message}, socket) do
    push(socket, "scheduled.posted", %{"message_id" => message.id, "topic_id" => message.topic_id})

    {:noreply, socket}
  end

  def handle_info({:api_token_revoked, id}, socket) do
    push(socket, "token.revoked", %{"token_id" => id})
    {:noreply, socket}
  end

  def handle_info({:settings_changed, keys}, socket) do
    case Enum.filter(keys, &(&1 in @client_settings)) do
      [] -> :ok
      keys -> push(socket, "settings.changed", %{"keys" => Enum.map(keys, &Atom.to_string/1)})
    end

    {:noreply, socket}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp counter(user) do
    %{count: count, level: level} = Reading.for_you(user)
    %{"count" => count, "level" => level && Atom.to_string(level)}
  end
end
