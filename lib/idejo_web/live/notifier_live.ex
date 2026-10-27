# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NotifierLive do
  @moduledoc """
  Live notifications (steward decision, 2026-10-23): one small LiveView per signed-in page,
  rendered by the root layout outside the page's main LiveView, so live navigation keeps it. It listens on the
  user's channel (`Idejo.Notifications.subscribe/1`) and hands each notification to the
  `Notifier` hook (`assets/js/notifier.js`), which shows it as a bubble and brings the
  sidebar up to date (`/sidebar`). The bubbles are drawn by the hook: this view only renders
  their empty container, so a page costs nothing until something happens.
  """
  use IdejoWeb, :live_view

  alias Idejo.Notifications

  on_mount {IdejoWeb.UserAuth, :mount_current_scope}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user
    if user && connected?(socket), do: Notifications.subscribe(user)
    {:ok, socket}
  end

  @impl true
  def handle_info({:notification, live}, socket),
    do: {:noreply, push_event(socket, "notification", bubble(live))}

  @doc """
  What a bubble shows of a live notification (`Idejo.Notifications.live/0`): its kind, a
  sentence, the message's opening words, where it leads, and the emoji of a reaction.
  """
  @spec bubble(Notifications.live()) :: map()
  def bubble(live) do
    %{
      kind: live.kind,
      text: text(live.kind, live.author_name, live.topic_title),
      excerpt: live.excerpt,
      href: href(live),
      topic_id: live.topic_id,
      emoji: live.emoji
    }
  end

  # Where the reader left off in the topic (`/m/{id}?unread`); a reaction, to the message.
  defp href(%{kind: "reaction", message_id: id}), do: ~p"/m/#{id}"
  defp href(%{message_id: id}), do: ~p"/m/#{id}?unread"

  defp text("mention", name, topic),
    do: gettext("%{name} mentioned you in “%{topic}”", name: name, topic: topic)

  defp text("reply", name, topic),
    do: gettext("%{name} replied to you in “%{topic}”", name: name, topic: topic)

  defp text("role_mention", name, topic),
    do: gettext("%{name} mentioned one of your roles in “%{topic}”", name: name, topic: topic)

  defp text("reaction", name, topic),
    do: gettext("%{name} reacted to your message in “%{topic}”", name: name, topic: topic)

  defp text(_follow, name, topic),
    do: gettext("%{name} posted in “%{topic}”", name: name, topic: topic)

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="notifier"
      phx-hook="Notifier"
      phx-update="ignore"
      data-dismiss={gettext("Dismiss")}
      data-sidebar={~p"/sidebar"}
    >
      <%!-- AX-02: each bubble is read out once, as it appears. --%>
      <div id="bubbles" class="bubbles" aria-live="polite" aria-relevant="additions"></div>
    </div>
    """
  end
end
