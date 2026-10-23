# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicLive do
  @moduledoc """
  A topic's messages, live (TP-04), with the composer for those who may post (M3).

  The topic page stays a controller (steward decision for M3): it embeds this LiveView with
  `live_render/3` and a session of `"topic_id"` and, after "Reply", `"reply_to_id"`. Its first
  render is the full list in the HTML, so the page reads without JavaScript (AX-04, CL-02).

  Connected, it subscribes to the topic's events before it loads the messages, so nothing
  posted in between is missed. Each `{:message, message}` updates that message in place or
  adds it at the end. A dropped connection reconnects by itself and mounts again, which loads
  the messages afresh: that is the catch-up of anything missed while away.

  Rights are checked at mount and again whenever the permission grid changes
  (`Idejo.Access.subscribe_permissions/0`): a viewer who lost the view right then sees the
  list emptied and gets no more events.

  **The composer** (GM-02, GM-07, GM-08) is a plain text box with no chrome; its placeholder
  names the keys. It is the author's open message, in place: the messages before it, then
  the composer (under the author's name), then the replies that came after, which push it
  up. With no open message it sits at the end. The `Composer` hook (`assets/js/composer.js`)
  sends the whole text on Enter, or with `"break"` on Ctrl+Enter or a third Enter in a row,
  to `Idejo.Messages.commit/4` and keeps it in the box; the reply tells it whether the
  message closed (GM-05).

  **For assistive technology** (AX-02, AX-03) the open state exists only as text: a hidden
  live region announces each message once when it opens and once when it closes, never at
  appends; open messages read "still being written"; and the composer is described by the
  time left in the author's window, updated every second while it runs.

  **Inline links** (TP-10): `@user`, `+role`, `#topic`, `/category` and `$tag` link to their
  pages. With JavaScript, the `InlineLinks` hook turns a click on one into `"show_card"`, and
  its card (`IdejoWeb.InlineCards`) opens here in a `<dialog>` (`InlineCard` hook) instead of
  leaving the topic; without it, or when the reader may not view it, the link is followed.
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.Scheduling
  alias Idejo.Reading
  alias Idejo.Repo
  alias IdejoWeb.Admin
  alias IdejoWeb.ImageUploads
  alias IdejoWeb.MessageModerationComponents
  alias IdejoWeb.ReactionComponents
  alias IdejoWeb.UserComponents

  on_mount {IdejoWeb.UserAuth, :mount_current_scope}

  @impl true
  def mount(_params, %{"topic_id" => topic_id} = session, socket) do
    user = user(socket)

    case Forum.get_viewable_topic(user, topic_id) do
      nil ->
        {:ok,
         assign(socket,
           topic: nil,
           can_post?: false,
           lost_access?: false,
           messages: [],
           roles: %{},
           editing: nil,
           refocus: nil,
           can_moderate?: false,
           announcement: nil,
           now: DateTime.utc_now(),
           tick: nil,
           forks: %{},
           can_fork?: false,
           card: nil,
           image_error: nil,
           reactions: %{},
           can_react?: false,
           picker: nil,
           viewable_replies: MapSet.new(),
           moderating: nil,
           confirm_delete: nil,
           selected: nil,
           select_for: nil,
           move_to: nil,
           move_query: "",
           move_results: [],
           move_error: nil,
           first_unread: nil,
           unread_line?: false,
           pending: [],
           schedule: nil
         )}

      topic ->
        # First subscribe, then load: a message posted in between arrives as an event.
        if connected?(socket), do: subscribe(topic, user)

        can_post? = Forum.can_post?(user, topic)

        {:ok,
         socket
         |> assign(topic: topic, can_post?: can_post?, lost_access?: false, roles: %{})
         |> assign(:can_moderate?, user != nil and Access.can?(user, :moderate, topic.category))
         |> assign(:can_fork?, Forum.list_startable_categories(user) != [])
         |> assign(editing: nil, refocus: nil, editor_mode: :write, preview_html: "")
         |> assign(announcement: nil, now: DateTime.utc_now(), tick: nil, card: nil)
         |> assign(:reply_to, can_post? && Forum.get_topic_message(topic, session["reply_to_id"]))
         |> put_messages(Forum.list_messages(topic))
         |> put_first_unread(session["first_unread"])
         |> put_forks()
         |> assign(can_react?: can_react?(user, topic), picker: nil)
         |> assign(
           moderating: nil,
           confirm_delete: nil,
           selected: nil,
           select_for: nil,
           move_to: nil,
           move_query: "",
           move_results: [],
           move_error: nil
         )
         |> put_reactions()
         |> assign(schedule: nil, schedule_error: nil)
         |> put_pending()
         |> ImageUploads.allow(:composer_image, can_post?)
         |> ImageUploads.allow(:edit_image, can_post?)
         |> sync_composer()
         |> schedule_tick()}
    end
  end

  defp user(socket), do: socket.assigns.current_scope && socket.assigns.current_scope.user

  # `!schedule` (steward decision, 2026-10-23): the viewer's messages waiting to be posted
  # here, which only they see.
  defp put_pending(%{assigns: %{can_post?: true}} = socket),
    do: assign(socket, :pending, Scheduling.list_pending(user(socket), socket.assigns.topic))

  defp put_pending(socket), do: assign(socket, :pending, [])

  # Where the reader left off (TP-07; steward decision, 2026-10-23): the oldest message unread
  # when the page was asked for, which the controller found before marking the topic read.
  # The "N unread messages" line shows above it until the `UnreadLine` hook says it faded.
  defp put_first_unread(socket, %{id: id, count: count}) do
    if Enum.any?(socket.assigns.messages, &(&1.id == id)),
      do: assign(socket, first_unread: %{id: id, count: count}, unread_line?: true),
      else: put_first_unread(socket, nil)
  end

  defp put_first_unread(socket, _none),
    do: assign(socket, first_unread: nil, unread_line?: false)

  defp subscribe(topic, user) do
    Messages.subscribe(topic.id)
    Access.subscribe_permissions()
    # While this view lives, the user's open message here stays open (GM-12).
    if user, do: Messages.Authors.present(topic.id, user.id)
    # Whatever came between the page and the connection is seen now (TP-07).
    Reading.mark_read(user, topic)
  end

  # TP-17: any signed-in, verified reader reacts, while the topic takes changes.
  defp can_react?(nil, _topic), do: false
  defp can_react?(user, topic), do: Idejo.Accounts.confirmed?(user) and topic.state == "open"

  # TP-17: the reactions of every message shown, in one query; later changes come as events.
  defp put_reactions(socket) do
    ids = Enum.map(socket.assigns.messages, & &1.id)
    assign(socket, :reactions, Idejo.Reactions.summaries(ids))
  end

  # TP-09: each message's "continued in" topics that the viewer may see.
  defp put_forks(socket) do
    ids = Enum.map(socket.assigns.messages, & &1.id)
    assign(socket, :forks, Forum.list_forks(user(socket), ids))
  end

  defp put_messages(socket, messages) do
    socket
    |> assign(:messages, messages)
    |> add_roles(messages)
    |> put_viewable_replies(messages)
  end

  # TP-15: a reply may lead to another topic after a move; its quote shows only to readers who
  # may view that topic. Messages of this topic need no query (NF-01).
  defp put_viewable_replies(socket, messages) do
    topic_id = socket.assigns.topic.id

    foreign =
      for %{reply_to: %Messages.Message{topic_id: other} = reply} <- messages,
          other != topic_id,
          do: reply.id

    assign(socket, :viewable_replies, Forum.viewable_message_ids(user(socket), foreign))
  end

  # The role next to each author's name (GM-07): their highest-ranked one that is "Visible
  # next to name" (steward decision, 2026-10-23), or none.
  # Only authors not seen yet are looked up, so most events cost no query (NF-01).
  defp add_roles(socket, messages) do
    missing =
      messages
      |> Enum.map(& &1.author)
      |> Enum.uniq_by(& &1.id)
      |> Enum.reject(&Map.has_key?(socket.assigns.roles, &1.id))

    if missing == [], do: socket, else: assign_roles(socket, missing)
  end

  defp assign_roles(socket, missing) do
    roles =
      missing
      |> Access.roles_of_users()
      |> Map.new(fn {id, roles} -> {id, Access.shown_role(roles)} end)

    assign(socket, :roles, Map.merge(socket.assigns.roles, roles))
  end

  # A reconnect keeps the author's open message (within the grace, GM-12): the hook is told
  # what the server holds of it, or that nothing is open, when it closed while they were away.
  defp sync_composer(%{assigns: %{can_post?: true}} = socket) do
    if connected?(socket) do
      body =
        case open_message(socket.assigns.messages, user(socket)) do
          %{body_md: body} -> body
          nil -> ""
        end

      push_event(socket, "composer_sent", %{body: body})
    else
      socket
    end
  end

  defp sync_composer(socket), do: socket

  defp open_message(_messages, nil), do: nil

  defp open_message(messages, user),
    do: Enum.find(messages, &(&1.state == "open" and &1.author_id == user.id))

  @impl true
  def handle_info({:message, message}, socket) do
    # Loaded once by the broadcast (NF-01); this costs nothing then.
    message = Repo.preload(message, Messages.shown())
    old = Enum.find(socket.assigns.messages, &(&1.id == message.id))
    # A message that arrives while the topic is open is read (TP-07); appends change nothing.
    if is_nil(old), do: Reading.mark_read(user(socket), socket.assigns.topic)

    # A new message makes the topic's name glow in the sidebar (the Notifier hook listens
    # on the window; steward decision, 2026-10-23).
    socket =
      if is_nil(old),
        do: push_event(socket, "topic_activity", %{topic_id: socket.assigns.topic.id}),
        else: socket

    {:noreply,
     socket
     |> announce(old, message)
     |> put_messages(upsert(socket.assigns.messages, message))
     |> schedule_tick()}
  end

  # The time left in the author's window, for the composer's description (AX-03).
  def handle_info(:tick, socket) do
    {:noreply, socket |> assign(now: DateTime.utc_now(), tick: nil) |> schedule_tick()}
  end

  # A moderator locked, unlocked, pinned, unpinned (TP-14) or moved (TP-15) the topic: the
  # composer goes or comes back with the post right, and a viewer who may not view its new
  # category loses it, as when permissions change.
  def handle_info({:topic_changed, _topic_id}, %{assigns: %{topic: nil}} = socket),
    do: {:noreply, socket}

  def handle_info({:topic_changed, topic_id}, socket) do
    case Forum.get_viewable_topic(user(socket), topic_id) do
      nil ->
        Messages.unsubscribe(topic_id)

        {:noreply,
         assign(socket,
           topic: nil,
           can_post?: false,
           can_react?: false,
           lost_access?: true,
           messages: []
         )}

      topic ->
        {:noreply,
         assign(socket,
           topic: topic,
           can_post?: Forum.can_post?(user(socket), topic),
           can_react?: can_react?(user(socket), topic)
         )}
    end
  end

  # TP-17: someone reacted; the summary was worked out once, by them (NF-01).
  def handle_info({:reactions, message_id, summary}, socket),
    do:
      {:noreply,
       assign(socket, :reactions, Map.put(socket.assigns.reactions, message_id, summary))}

  # TP-15: messages moved into or out of this topic: read it again.
  def handle_info({:messages_moved, _topic_id}, %{assigns: %{topic: nil}} = socket),
    do: {:noreply, socket}

  def handle_info({:messages_moved, topic_id}, socket) do
    case Forum.get_viewable_topic(user(socket), topic_id) do
      nil ->
        {:noreply, socket}

      topic ->
        messages = Forum.list_messages(topic)
        ids = MapSet.new(messages, & &1.id)
        selected = socket.assigns.selected && MapSet.intersection(socket.assigns.selected, ids)

        {:noreply,
         socket
         |> assign(topic: topic, selected: selected)
         |> put_messages(messages)
         |> put_forks()
         |> put_reactions()
         |> sync_composer()}
    end
  end

  # Someone started a topic from one of these messages (TP-09).
  def handle_info({:forked, _message_id}, socket), do: {:noreply, put_forks(socket)}

  # A scheduled message was added, cancelled or posted: only its author's views reload.
  def handle_info({:scheduled, author_id}, socket) do
    if mine?(socket, %{author_id: author_id}),
      do: {:noreply, put_pending(socket)},
      else: {:noreply, socket}
  end

  # The grid changed: the viewer may have lost the view or post right since mount.
  def handle_info(:permissions_changed, %{assigns: %{topic: nil}} = socket),
    do: {:noreply, socket}

  def handle_info(:permissions_changed, socket) do
    user = user(socket)

    case Forum.get_viewable_topic(user, socket.assigns.topic.id) do
      nil ->
        Messages.unsubscribe(socket.assigns.topic.id)

        {:noreply,
         assign(socket,
           topic: nil,
           can_post?: false,
           can_react?: false,
           lost_access?: true,
           messages: []
         )}

      topic ->
        {:noreply,
         socket
         |> assign(
           can_post?: Forum.can_post?(user, topic),
           can_moderate?: user != nil and Access.can?(user, :moderate, topic.category),
           can_fork?: Forum.list_startable_categories(user) != []
         )
         |> put_forks()}
    end
  end

  # No countdown is shown (GM-07); the window's end only matters to Ctrl+Enter, which the
  # server checks. Its text equivalent is the composer's description (AX-03).
  def handle_info({:window_ended, _message_id}, socket),
    do: {:noreply, assign(socket, :now, DateTime.utc_now())}

  # AX-02: a message is announced when it opens and when it closes, never at an append or
  # an edit. One posted closed opens and closes at once, so it is announced once.
  defp announce(socket, old, message) do
    text =
      case {old && old.state, message.state} do
        {nil, "open"} -> opened_text(socket, message)
        {nil, "closed"} -> posted_text(socket, message)
        {"open", "closed"} -> closed_text(socket, message)
        _ -> nil
      end

    if text do
      # A new id each time, so the same words twice in a row are still read out.
      assign(socket, :announcement, {System.unique_integer([:positive]), text})
    else
      socket
    end
  end

  defp opened_text(socket, message) do
    if mine?(socket, message),
      do: gettext("You started a message."),
      else: gettext("%{name} started a message.", name: message.author.display_name)
  end

  defp closed_text(socket, message) do
    if mine?(socket, message),
      do: gettext("Your message is complete."),
      else: gettext("%{name}’s message is complete.", name: message.author.display_name)
  end

  defp posted_text(socket, message) do
    if mine?(socket, message),
      do: gettext("You posted a message."),
      else: gettext("New message from %{name}.", name: message.author.display_name)
  end

  # `!new-topic` (steward decision, 2026-10-23): "New topic from this" (TP-09) from the
  # message it replied to, else from the message itself; its text becomes the first message.
  defp new_topic_from(socket, message) do
    source_id = message.reply_to_id || message.id
    redirect(socket, to: ~p"/m/#{source_id}/new-topic?from=#{message.id}")
  end

  defp mine?(socket, message) do
    user = user(socket)
    user != nil and user.id == message.author_id
  end

  # One timer at a time, only while the viewer's own open message is inside its window.
  defp schedule_tick(%{assigns: %{tick: nil}} = socket) do
    case open_message(socket.assigns.messages, user(socket)) do
      %{closes_at: closes_at} ->
        if connected?(socket) and DateTime.after?(closes_at, DateTime.utc_now()),
          do: assign(socket, :tick, Process.send_after(self(), :tick, 1000)),
          else: socket

      nil ->
        socket
    end
  end

  defp schedule_tick(socket), do: socket

  # Messages keep their place; a new one goes at the end (GM-08: ordered by first commit).
  defp upsert(messages, message) do
    if Enum.any?(messages, &(&1.id == message.id)),
      do: Enum.map(messages, &if(&1.id == message.id, do: message, else: &1)),
      else: messages ++ [message]
  end

  @impl true
  def handle_event("commit", %{"body" => body} = params, socket) do
    %{topic: topic, reply_to: reply_to} = socket.assigns
    opts = [break: params["break"] == true, reply_to_id: reply_to && reply_to.id]
    then = params["then"]

    case Messages.commit(user(socket), topic, body, opts) do
      {:ok, nil} ->
        {:reply, %{closed: false, body: ""}, socket}

      # `!new-topic`: sent, then on to the new topic (steward decision, 2026-10-23).
      {:ok, message} when then == "new_topic" ->
        {:reply, %{closed: message.state == "closed", body: message.body_md},
         new_topic_from(socket, message)}

      # The message itself arrives like everyone else's, as an event.
      {:ok, message} ->
        {:reply, %{closed: message.state == "closed", body: message.body_md},
         assign(socket, :reply_to, nil)}

      {:error, :forbidden} ->
        {:reply, %{error: true},
         socket
         |> assign(:can_post?, false)
         |> put_flash(:error, gettext("You cannot post in this topic."))}

      # SP-05: the text stays in the composer, unsent; Enter again a little later.
      {:error, :rate_limited} ->
        {:reply, %{error: true},
         put_flash(
           socket,
           :error,
           gettext("You are sending very fast. Wait a moment, then press Enter again.")
         )}

      {:error, _changeset} ->
        {:reply, %{error: true}, socket}
    end
  end

  # `!new-topic` with nothing new to send: the topic starts from the open message.
  def handle_event("new_topic", _params, socket) do
    case open_message(socket.assigns.messages, user(socket)) do
      nil ->
        {:noreply,
         put_flash(socket, :error, gettext("Write your message first, then choose !new-topic."))}

      message ->
        {:noreply, new_topic_from(socket, message)}
    end
  end

  # `!schedule`: the text not sent yet, asked for its delay in a dialog.
  def handle_event("open_schedule", %{"body" => body}, socket) when is_binary(body) do
    if String.trim(body) == "",
      do:
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "Only text not sent yet can be scheduled: write it first, then choose !schedule."
           )
         )},
      else: {:noreply, assign(socket, schedule: %{body: body}, schedule_error: nil)}
  end

  def handle_event("hide_schedule", _params, socket),
    do: {:noreply, assign(socket, schedule: nil, schedule_error: nil)}

  def handle_event(
        "schedule",
        %{"hours" => hours},
        %{assigns: %{schedule: %{body: body}}} = socket
      ) do
    %{topic: topic, reply_to: reply_to} = socket.assigns

    with {:ok, seconds} <- Scheduling.parse_hours(hours),
         {:ok, _scheduled} <-
           Scheduling.schedule(user(socket), topic, body, seconds,
             reply_to_id: reply_to && reply_to.id
           ) do
      {:noreply,
       socket
       |> assign(schedule: nil, schedule_error: nil, reply_to: nil)
       |> push_event("composer_scheduled", %{body: body})}
    else
      :error ->
        {:noreply,
         assign(socket,
           schedule_error:
             gettext("Enter a number of hours above 0, at most %{max}.",
               max: Scheduling.max_hours()
             )
         )}

      {:error, :rate_limited} ->
        {:noreply,
         assign(socket,
           schedule_error: gettext("You are sending very fast. Wait a moment, then try again.")
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(schedule: nil, schedule_error: nil)
         |> put_flash(:error, gettext("You cannot post in this topic."))}
    end
  end

  def handle_event("schedule", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_scheduled", %{"id" => id}, socket) when is_binary(id) do
    if user(socket), do: Scheduling.cancel(user(socket), id)
    {:noreply, put_pending(socket)}
  end

  # TP-10: a click on an inline link opens its card in a dialog. The reply says whether it
  # did; when not (the reader may not view it), the browser follows the link.
  def handle_event("show_card", %{"kind" => kind, "ref" => ref}, socket)
      when is_binary(kind) and is_binary(ref) do
    topic = socket.assigns.topic
    return_to = topic && ~p"/t/#{topic.id}/#{topic.slug}"

    case IdejoWeb.InlineCards.load(kind, ref, user(socket), return_to: return_to) do
      nil -> {:reply, %{shown: false}, socket}
      card -> {:reply, %{shown: true}, assign(socket, :card, card)}
    end
  end

  def handle_event("hide_card", _params, socket), do: {:noreply, assign(socket, :card, nil)}

  # The "N unread messages" line has faded (`UnreadLine` hook): it goes for good.
  def handle_event("unread_line_done", _params, socket),
    do: {:noreply, assign(socket, :unread_line?, false)}

  # TP-17: add a reaction, or take it back. The new summary reaches every viewer as an event.
  def handle_event("react", %{"id" => id, "emoji" => emoji}, socket)
      when is_binary(id) and is_binary(emoji) do
    with true <- socket.assigns.can_react?,
         %Messages.Message{} = message <- Enum.find(socket.assigns.messages, &(&1.id == id)),
         {:ok, _summary} <- Idejo.Reactions.toggle(user(socket), message, emoji) do
      {:noreply, assign(socket, :picker, nil)}
    else
      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("You have reacted a lot lately. Please wait a little.")
         )}

      _ ->
        {:noreply, assign(socket, :picker, nil)}
    end
  end

  # The + picker: the server only opens and closes it; the browser draws and searches it.
  def handle_event("emoji_picker", %{"id" => id}, socket) when is_binary(id),
    do: {:noreply, assign(socket, :picker, %{message_id: id})}

  def handle_event("close_picker", _params, socket), do: {:noreply, assign(socket, :picker, nil)}

  # A topic's card: Follow / Unfollow (TP-13), then the card again.
  def handle_event("card_" <> action, %{"id" => id}, socket) when action in ~w(follow unfollow) do
    user = user(socket)

    with %{} <- user,
         %{} = topic <- Forum.get_viewable_topic(user, id) do
      :ok =
        if action == "follow",
          do: Reading.follow(user, topic),
          else: Reading.unfollow(user, topic)

      {:noreply, assign(socket, :card, IdejoWeb.InlineCards.load("topic", id, user))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_reply", _params, socket),
    do: {:noreply, assign(socket, :reply_to, nil)}

  # A moderator closes someone's open message (GM-16) or deletes a message (MO-02), with an
  # optional reason for the log. The changed message arrives as an event.
  def handle_event("moderate_message", %{"message_id" => id, "do" => action} = params, socket) do
    message = Enum.find(socket.assigns.messages, &(&1.id == id))
    reason = params["reason"]

    result =
      case {action, message} do
        {_, nil} -> :error
        {"close", %{state: "open"}} -> Messages.close_as_moderator(user(socket), message, reason)
        {"delete", _} -> Messages.delete_as_moderator(user(socket), message, reason)
        _ -> :error
      end

    case result do
      {:ok, _} -> {:noreply, assign(socket, :moderating, nil)}
      _ -> {:noreply, put_flash(socket, :error, gettext("This could not be done."))}
    end
  end

  # A message's "Moderate", as a card over the page (steward decision, 2026-10-23).
  def handle_event("open_moderate", %{"id" => id}, socket) when is_binary(id) do
    if socket.assigns.can_moderate? and Enum.any?(socket.assigns.messages, &(&1.id == id)),
      do: {:noreply, assign(socket, :moderating, id)},
      else: {:noreply, socket}
  end

  def handle_event("close_moderate", _params, socket),
    do: {:noreply, assign(socket, :moderating, nil)}

  # Choose messages to move (TP-15; the opening message never moves) or to delete (MO-02;
  # steward decision, 2026-10-23: not the moderator's own messages, nor deleted ones).
  def handle_event(
        "start_selecting",
        %{"id" => id} = params,
        %{assigns: %{can_moderate?: true}} = socket
      ) do
    select_for = if params["for"] == "delete", do: :delete, else: :move
    socket = assign(socket, moderating: nil, select_for: select_for)
    selected = if selectable?(socket, id), do: MapSet.new([id]), else: MapSet.new()
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event(
        "toggle_select",
        %{"id" => id},
        %{assigns: %{selected: %MapSet{} = selected}} = socket
      ) do
    selected =
      cond do
        not selectable?(socket, id) -> selected
        MapSet.member?(selected, id) -> MapSet.delete(selected, id)
        true -> MapSet.put(selected, id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("cancel_selecting", _params, socket),
    do: {:noreply, assign(socket, selected: nil, select_for: nil, move_to: nil, move_error: nil)}

  def handle_event(
        "delete_selected",
        params,
        %{assigns: %{selected: %MapSet{} = selected, select_for: :delete}} = socket
      ) do
    case Messages.delete_many_as_moderator(
           user(socket),
           socket.assigns.topic,
           MapSet.to_list(selected),
           params["reason"]
         ) do
      {:ok, deleted} ->
        {:noreply,
         socket
         |> assign(selected: nil, select_for: nil)
         |> put_flash(
           :info,
           ngettext("1 message deleted.", "%{count} messages deleted.", length(deleted))
         )}

      _error ->
        {:noreply, put_flash(socket, :error, gettext("This could not be done."))}
    end
  end

  def handle_event("delete_selected", _params, socket), do: {:noreply, socket}

  def handle_event("move_to", %{"to" => to}, %{assigns: %{selected: %MapSet{}}} = socket)
      when to in ~w(new existing) do
    socket = assign(socket, move_to: String.to_existing_atom(to), move_error: nil, move_query: "")

    if to == "existing",
      do: {:noreply, search_targets(socket, "")},
      else: {:noreply, socket}
  end

  def handle_event("search_targets", %{"q" => query}, socket) when is_binary(query),
    do: {:noreply, search_targets(socket, String.slice(query, 0, 200))}

  def handle_event("close_move", _params, socket),
    do: {:noreply, assign(socket, move_to: nil, move_error: nil)}

  def handle_event(
        "move_selected",
        params,
        %{assigns: %{selected: %MapSet{} = selected}} = socket
      ) do
    target =
      case params do
        %{"to" => "new"} ->
          {:new, Map.take(params, ["title", "category_id"])}

        %{"to" => "existing", "topic_id" => id} ->
          case Forum.get_viewable_topic(user(socket), id) do
            nil -> nil
            topic -> {:existing, topic}
          end

        _ ->
          nil
      end

    result =
      target &&
        Forum.move_messages(
          user(socket),
          socket.assigns.topic,
          MapSet.to_list(selected),
          target,
          params["reason"]
        )

    case result do
      {:ok, topic} ->
        {:noreply,
         socket
         |> assign(selected: nil, move_to: nil, move_error: nil)
         |> put_flash(
           :info,
           ngettext(
             "1 message moved to “%{title}”.",
             "%{count} messages moved to “%{title}”.",
             MapSet.size(selected),
             title: topic.title
           )
         )}

      error ->
        {:noreply, assign(socket, :move_error, move_error(error))}
    end
  end

  def handle_event("move_selected", _params, socket), do: {:noreply, socket}

  # Editing one's own closed message (GM-10); open ones are edited in the composer.
  def handle_event("edit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.messages, &(&1.id == id)) do
      %{state: "closed", deleted_at: nil} = message ->
        form = to_form(%{"body" => message.body_md}, as: :edit)
        {:noreply, assign(socket, editing: {id, form}, editor_mode: :write, preview_html: "")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, close_editor(socket)}

  def handle_event(
        "validate_edit",
        %{"edit" => params},
        %{assigns: %{editing: {id, _}}} = socket
      ),
      do:
        {:noreply,
         socket
         |> assign(:editing, {id, to_form(params, as: :edit)})
         |> ImageUploads.check(:edit_image)}

  # TP-12: an image pasted or dropped into the composer was refused before uploading.
  def handle_event("validate_image", _params, socket),
    do: {:noreply, ImageUploads.check(socket, :composer_image)}

  def handle_event(
        "editor_mode",
        %{"mode" => "preview"},
        %{assigns: %{editing: {_, form}}} = socket
      ) do
    html =
      Messages.Body.to_html(form.params["body"] || "",
        author: user(socket),
        category_id: socket.assigns.topic.category_id
      )

    {:noreply, assign(socket, editor_mode: :preview, preview_html: html)}
  end

  # TP-10: suggestions while typing an inline link, the people of this topic first.
  def handle_event("suggest", params, socket),
    do: IdejoWeb.Suggestions.reply(socket, params, topic_id: socket.assigns.topic.id)

  def handle_event("editor_mode", %{"mode" => "write"}, socket),
    do: {:noreply, assign(socket, :editor_mode, :write)}

  def handle_event("save_edit", %{"edit" => %{"body" => body} = params}, socket) do
    {id, _form} = socket.assigns.editing
    message = Enum.find(socket.assigns.messages, &(&1.id == id))
    user = user(socket)

    # The author edits (GM-10); a moderator edits someone else's message (MO-02), logged.
    result =
      if message.author_id == user.id,
        do: Messages.edit(user, message, body),
        else: Messages.edit_as_moderator(user, message, body, params["reason"])

    case result do
      # The edited message arrives like everyone else's view of it, as an event.
      {:ok, _message} ->
        {:noreply, close_editor(socket)}

      # Steward decision, 2026-10-23: the author emptied their message, so ask whether to
      # delete it; the editor stays open behind the question. Not the opening message.
      {:error, :blank}
      when message.author_id == user.id and message.id != hd(socket.assigns.messages).id ->
        {:noreply,
         assign(socket,
           editing: {id, to_form(%{"body" => body}, as: :edit)},
           confirm_delete: id
         )}

      {:error, :blank} ->
        form =
          %{"body" => body}
          |> to_form(as: :edit, errors: [body: {"can't be blank", []}], action: :validate)

        {:noreply, assign(socket, :editing, {id, form})}

      {:error, _} ->
        {:noreply,
         socket
         |> close_editor()
         |> put_flash(:error, gettext("This message cannot be edited."))}
    end
  end

  def handle_event("delete_own", _params, %{assigns: %{confirm_delete: id}} = socket)
      when is_binary(id) do
    message = Enum.find(socket.assigns.messages, &(&1.id == id))
    socket = assign(socket, :confirm_delete, nil)

    # The deleted message arrives as an event, like everyone else's view of it.
    case message && Messages.delete_own(user(socket), message) do
      # AX-01: the focus moves to the placeholder that replaces the editor.
      {:ok, _message} ->
        {:noreply, assign(socket, editing: nil, refocus: id)}

      _error ->
        {:noreply,
         socket
         |> close_editor()
         |> put_flash(:error, gettext("This message cannot be deleted."))}
    end
  end

  def handle_event("delete_own", _params, socket), do: {:noreply, socket}

  # "No", Escape or a click outside: back to the editor, the text still empty.
  def handle_event("cancel_delete_own", _params, socket),
    do: {:noreply, assign(socket, :confirm_delete, nil)}

  # AX-01: the keyboard focus goes back to the message's Edit button, which the editor
  # replaced (it takes the focus when it is mounted again).
  defp close_editor(%{assigns: %{editing: {id, _}}} = socket),
    do: assign(socket, editing: nil, refocus: id)

  defp close_editor(socket), do: assign(socket, :editing, nil)

  defp selectable?(socket, id) do
    case Enum.find(socket.assigns.messages, &(&1.id == id)) do
      nil -> false
      message -> selectable_in_view?(socket.assigns, message)
    end
  end

  # Which messages may be chosen: to move, any but the opening one (TP-15); to delete, any
  # not deleted and not the moderator's own (MO-02).
  defp selectable_in_view?(%{select_for: :delete} = assigns, message),
    do: is_nil(message.deleted_at) and message.author_id != assigns.current_scope.user.id

  defp selectable_in_view?(assigns, message), do: message.id != List.first(assigns.messages).id

  defp search_targets(socket, query) do
    results = Forum.search_move_targets(user(socket), query, socket.assigns.topic.id)
    assign(socket, move_query: query, move_results: results)
  end

  defp move_error({:error, %Ecto.Changeset{}}), do: gettext("The new thread needs a title.")
  defp move_error({:error, :opening}), do: gettext("The opening message cannot be moved.")

  defp move_error({:error, :forbidden}),
    do: gettext("You do not moderate the category of that thread.")

  defp move_error(_error), do: gettext("Choose a thread to move the messages to.")

  @impl true
  def render(assigns) do
    mine = open_message(assigns.messages, assigns.current_scope && assigns.current_scope.user)
    {before, after_} = split(assigns.messages, mine)
    # TP-12: allowed at mount for those who could post then; nil otherwise.
    uploads = assigns[:uploads] || %{}

    assigns =
      assign(assigns,
        moderated:
          assigns.moderating && Enum.find(assigns.messages, &(&1.id == assigns.moderating)),
        before: before,
        mine: mine,
        later: after_,
        deleted_runs: Map.merge(deleted_runs(before), deleted_runs(after_)),
        composer_upload: uploads[:composer_image],
        edit_upload: uploads[:edit_image]
      )

    ~H"""
    <div id="topic-live" phx-hook="InlineLinks" data-topic-id={@topic && @topic.id}>
      <dialog
        :if={@card}
        id="inline-card"
        class="modal"
        phx-hook="InlineCard"
        aria-labelledby="inline-card-name"
      >
        <div class="modal-box inline-card">
          <IdejoWeb.CardComponents.inline_card card={@card} />
          <div class="modal-action">
            <button type="button" class="btn btn-sm btn-ghost" phx-click="hide_card">
              {gettext("Close")}
            </button>
          </div>
        </div>
      </dialog>
      <ReactionComponents.emoji_picker :if={@picker && @can_react?} picker={@picker} />
      <.delete_own_dialog :if={@confirm_delete} />
      <.schedule_dialog :if={@schedule} schedule={@schedule} error={@schedule_error} />
      <MessageModerationComponents.moderate_card
        :if={@can_moderate? && @moderated}
        message={@moderated}
        own?={@moderated.author_id == @current_scope.user.id}
        movable?={@moderated.id != List.first(@messages).id}
      />
      <MessageModerationComponents.move_banner
        :if={@can_moderate? && @selected && @select_for == :move}
        count={MapSet.size(@selected)}
      />
      <MessageModerationComponents.delete_banner
        :if={@can_moderate? && @selected && @select_for == :delete}
        count={MapSet.size(@selected)}
      />
      <MessageModerationComponents.move_dialog
        :if={@can_moderate? && @selected && @select_for == :move && @move_to}
        to={@move_to}
        count={MapSet.size(@selected)}
        categories={
          if @move_to == :new, do: Forum.list_moderated_categories(@current_scope.user), else: []
        }
        current_category_id={@topic.category_id}
        query={@move_query}
        results={@move_results}
        error={@move_error}
      />
      <%!-- AX-02: read out when a message opens or closes; the list itself is not live. --%>
      <div id="topic-announcer" role="status" aria-live="polite" aria-atomic="true" class="sr-only">
        <span :if={@announcement} id={"announcement-#{elem(@announcement, 0)}"}>
          {elem(@announcement, 1)}
        </span>
      </div>
      <.topic_nav
        :if={@topic && @messages != []}
        title={@topic.title}
        messages={@messages}
        first_unread={@first_unread}
        viewer={@current_scope && @current_scope.user}
      />
      <p :if={@lost_access?} id="topic-gone" role="status" class="opacity-70">
        {gettext("You can no longer view this topic.")}
      </p>

      <ol id="messages" class={["message-list", @topic && "cat-#{@topic.category_id}"]}>
        <li
          :for={message <- @before}
          :key={message.id}
          id={"message-#{message.id}"}
          hidden={@deleted_runs[message.id] == :rest and !@can_moderate?}
        >
          <.unread_line
            :if={@unread_line? and @first_unread.id == message.id}
            message_id={message.id}
            count={@first_unread.count}
          />
          <.message
            message={message}
            topic={@topic}
            can_post?={@can_post?}
            roles={@roles}
            viewer={@current_scope && @current_scope.user}
            can_moderate?={@can_moderate?}
            can_fork?={@can_fork?}
            forks={Map.get(@forks, message.id, [])}
            deleted_run={@deleted_runs[message.id]}
            editing={@editing}
            refocus={@refocus}
            editor_mode={@editor_mode}
            preview_html={@preview_html}
            edit_upload={@edit_upload}
            image_error={@image_error}
            reactions={Map.get(@reactions, message.id, [])}
            can_react?={@can_react?}
            selected={@selected && MapSet.member?(@selected, message.id)}
            selectable?={selectable_in_view?(assigns, message)}
            viewable_replies={@viewable_replies}
          />
        </li>
        <li :if={@can_post?} id={if @mine, do: "message-#{@mine.id}", else: "composer-slot"}>
          <.composer
            mine={@mine}
            pending={@pending}
            commands={IdejoWeb.ComposerCommands.for_composer(@composer_upload != nil, @can_fork?)}
            reply_to={@reply_to}
            roles={@roles}
            author={@current_scope.user}
            now={@now}
            upload={@composer_upload}
            image_error={@image_error}
          />
        </li>
        <li
          :for={message <- @later}
          :key={message.id}
          id={"message-#{message.id}"}
          hidden={@deleted_runs[message.id] == :rest and !@can_moderate?}
        >
          <.unread_line
            :if={@unread_line? and @first_unread.id == message.id}
            message_id={message.id}
            count={@first_unread.count}
          />
          <.message
            message={message}
            topic={@topic}
            can_post?={@can_post?}
            roles={@roles}
            viewer={@current_scope && @current_scope.user}
            can_moderate?={@can_moderate?}
            can_fork?={@can_fork?}
            forks={Map.get(@forks, message.id, [])}
            deleted_run={@deleted_runs[message.id]}
            editing={@editing}
            refocus={@refocus}
            editor_mode={@editor_mode}
            preview_html={@preview_html}
            edit_upload={@edit_upload}
            image_error={@image_error}
            reactions={Map.get(@reactions, message.id, [])}
            can_react?={@can_react?}
            selected={@selected && MapSet.member?(@selected, message.id)}
            selectable?={selectable_in_view?(assigns, message)}
            viewable_replies={@viewable_replies}
          />
        </li>
      </ol>

      <p :if={@flash["error"]} role="alert" class="alert alert-error mt-4">{@flash["error"]}</p>
      <%!-- TP-15: what a move did, for the moderator who did it. --%>
      <p :if={@flash["info"]} id="topic-info" role="status" class="alert alert-info mt-4">
        {@flash["info"]}
      </p>

      <div :if={@topic && !@can_post?} class="mt-8">
        <%= cond do %>
          <% @topic.state != "open" -> %>
            <p id="topic-closed" class="opacity-70">
              {gettext("This topic takes no new messages.")}
            </p>
          <% is_nil(@current_scope) -> %>
            <p id="sign-in-to-post">
              <.link href={~p"/users/sign-in"} class="link">
                {gettext("Sign in to take part.")}
              </.link>
            </p>
          <% true -> %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :messages, :list, required: true
  attr :first_unread, :map, default: nil
  attr :viewer, :any, required: true

  # The topic navigator (steward decision, 2026-10-23): once the title has scrolled away, a
  # card at the right with the title and links to the first message, the first unread, the
  # last message and the reader's own last one; where the right has no room for it (phones),
  # a small pill at the top right that opens it. Plain links to the messages' anchors
  # (TP-06); the `TopicNav` hook shows it, picks card or pill and scrolls. Without
  # JavaScript it stays hidden (the page reads the same without it, AX-04).
  defp topic_nav(assigns) do
    viewer_id = assigns.viewer && assigns.viewer.id

    assigns =
      assign(assigns,
        first: List.first(assigns.messages),
        last: List.last(assigns.messages),
        mine:
          viewer_id &&
            assigns.messages
            |> Enum.reverse()
            |> Enum.find(&(&1.author_id == viewer_id and is_nil(&1.deleted_at)))
      )

    ~H"""
    <nav
      id="topic-nav"
      class="topic-nav"
      aria-label={gettext("Topic navigation")}
      phx-hook="TopicNav"
      phx-mounted={JS.ignore_attributes(["data-shown", "data-mode", "data-open"])}
    >
      <button
        type="button"
        class="topic-nav-pill"
        aria-expanded="false"
        aria-controls="topic-nav-panel"
        phx-mounted={JS.ignore_attributes(["aria-expanded"])}
      >
        <.icon name="hero-queue-list" class="size-4" />
        <span class="sr-only">{gettext("Jump to a message")}</span>
      </button>
      <div id="topic-nav-panel" class="topic-nav-panel">
        <p class="topic-nav-title">{@title}</p>
        <ul class="topic-nav-links">
          <li>
            <a href={"#message-#{@first.id}"} id="topic-nav-first">
              <.icon name="hero-chevron-double-up" class="size-4" />{gettext("First message")}
            </a>
          </li>
          <li :if={@first_unread}>
            <a href={"#message-#{@first_unread.id}"} id="topic-nav-unread">
              <.icon name="hero-sparkles" class="size-4" />{gettext("First unread")}
            </a>
          </li>
          <li>
            <a href={"#message-#{@last.id}"} id="topic-nav-last">
              <.icon name="hero-chevron-double-down" class="size-4" />{gettext("Last message")}
            </a>
          </li>
          <li :if={@mine}>
            <a href={"#message-#{@mine.id}"} id="topic-nav-mine">
              <.icon name="hero-user" class="size-4" />{gettext("My last message")}
            </a>
          </li>
        </ul>
      </div>
    </nav>
    """
  end

  attr :message_id, :string, required: true, doc: "the message it stands above"
  attr :count, :integer, required: true

  # Where the reader left off (TP-07): a red line above the oldest message unread when they
  # opened the topic; the page opens centred on it (`UnreadLine` hook). It stays 4 s, then
  # fades (CSS) and goes.
  defp unread_line(assigns) do
    ~H"""
    <div id="unread-line" class="unread-line" phx-hook="UnreadLine" data-message-id={@message_id}>
      <span>
        {ngettext("1 unread message", "%{count} unread messages", @count)}
      </span>
    </div>
    """
  end

  # Who may edit this message: its author while it is closed (GM-10), or a moderator, someone
  # else's closed message (MO-02). Deleted messages are edited by nobody.
  defp edit_rights(%{message: message, viewer: viewer} = assigns) do
    editable? = viewer != nil and message.state == "closed" and is_nil(message.deleted_at)
    own? = viewer != nil and viewer.id == message.author_id

    [
      own_closed?: editable? and own? and assigns.can_post?,
      mod_edit?: editable? and not own? and assigns.can_moderate?
    ]
  end

  # MO-02: for readers, a run of deleted messages shows as one line, one run per kind (by a
  # moderator, or by their authors). Maps each deleted message's id to `{:first, count,
  # kind}` for the first of its run, `:rest` for the others.
  defp deleted_runs(messages) do
    messages
    |> Enum.chunk_by(&deleted_kind/1)
    |> Enum.filter(fn [first | _] -> first.deleted_at != nil end)
    |> Enum.flat_map(fn [first | rest] = run ->
      [{first.id, {:first, length(run), deleted_kind(first)}} | Enum.map(rest, &{&1.id, :rest})]
    end)
    |> Map.new()
  end

  defp deleted_kind(%{deleted_at: nil}), do: nil

  defp deleted_kind(message),
    do: if(Messages.deleted_by_author?(message), do: :author, else: :moderator)

  defp deleted_text({:first, count, :moderator}),
    do:
      ngettext(
        "Message deleted by a moderator",
        "%{count} messages deleted by a moderator",
        count
      )

  defp deleted_text({:first, count, :author}),
    do: ngettext("Message deleted by user", "%{count} messages deleted by user", count)

  # Steward decision, 2026-10-23: asked when the author saves their message with no text.
  # "No" closes the dialog natively (a `method="dialog"` form), so the focus goes back to the
  # editor; the dialog's close event tells the server.
  defp delete_own_dialog(assigns) do
    ~H"""
    <dialog
      id="delete-own-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="cancel_delete_own"
      aria-labelledby="delete-own-title"
    >
      <div class="modal-box inline-card">
        <h2 id="delete-own-title" class="inline-card-title">
          {gettext("Are you sure you want to delete your own message?")}
        </h2>
        <form method="dialog" class="modal-action">
          <button type="button" class="btn btn-sm btn-error" phx-click="delete_own">
            {gettext("Yes")}
          </button>
          <button class="btn btn-sm" autofocus>{gettext("No")}</button>
        </form>
      </div>
    </dialog>
    """
  end

  # The messages before the author's open message and the ones after it; with none open,
  # everything comes before and the composer goes to the end.
  defp split(messages, nil), do: {messages, []}

  defp split(messages, mine) do
    {before, [_mine | after_]} = Enum.split_while(messages, &(&1.id != mine.id))
    {before, after_}
  end

  attr :author, :map, required: true
  attr :roles, :map, required: true

  defp author_line(assigns) do
    assigns = assign(assigns, :role, Map.get(assigns.roles, assigns.author.id))

    ~H"""
    <span class="author-line">
      <UserComponents.avatar user={@author} size={:list} />
      <%!-- TP-10: the name opens the user's card, like an @mention (InlineLinks hook). --%>
      <a href={~p"/u/#{@author.id}"} class="author-name font-semibold">{@author.display_name}</a>
      <Admin.role_label :if={@role} role={@role} class="author-role" />
    </span>
    """
  end

  attr :message, :map, required: true
  attr :topic, :map, required: true
  attr :can_post?, :boolean, required: true
  attr :roles, :map, required: true
  attr :viewer, :any, required: true
  attr :can_moderate?, :boolean, required: true
  attr :can_fork?, :boolean, required: true
  attr :forks, :list, required: true
  attr :deleted_run, :any, default: nil
  attr :editing, :any, required: true
  attr :refocus, :string, default: nil, doc: "the message whose editor just closed (AX-01)"
  attr :editor_mode, :atom, required: true
  attr :preview_html, :string, required: true
  attr :edit_upload, :any, default: nil
  attr :image_error, :string, default: nil
  attr :reactions, :list, default: []
  attr :can_react?, :boolean, default: false
  attr :selected, :any, default: nil, doc: "nil outside choosing messages (TP-15, MO-02)"
  attr :selectable?, :boolean, default: false, doc: "a checkbox while choosing messages"
  attr :viewable_replies, :any, default: MapSet.new()

  # Open and closed messages look the same to readers (GM-07).
  defp message(assigns) do
    editing =
      case assigns.editing do
        {id, form} when id == assigns.message.id -> form
        _ -> nil
      end

    assigns = assign(assigns, [edit_form: editing] ++ edit_rights(assigns))

    ~H"""
    <%!-- MO-02: readers see a placeholder for a deleted message, one line for a run of them. --%>
    <p
      :if={@message.deleted_at && !@can_moderate? && match?({:first, _, _}, @deleted_run)}
      id={"message-#{@message.id}-deleted"}
      class="message-deleted"
      tabindex="-1"
      phx-mounted={@refocus == @message.id && JS.focus()}
    >
      {deleted_text(@deleted_run)}
    </p>
    <article
      :if={is_nil(@message.deleted_at) or @can_moderate?}
      aria-labelledby={"message-#{@message.id}-author"}
      class="message"
    >
      <p id={"message-#{@message.id}-author"} class="message-head">
        <%!-- Choosing messages to move (TP-15) or delete (MO-02). --%>
        <label :if={@selected != nil and @selectable?} class="move-select">
          <input
            type="checkbox"
            id={"select-#{@message.id}"}
            checked={@selected}
            phx-click="toggle_select"
            phx-value-id={@message.id}
          />
          <span class="sr-only">
            {gettext("Select the message by %{name}", name: @message.author.display_name)}
          </span>
        </label>
        <.author_line author={@message.author} roles={@roles} />
        <%!-- GM-07, AX-03: the open state has no visible sign, only this text. --%>
        <span :if={@message.state == "open"} class="sr-only">
          {gettext("(still being written)")}
        </span>
        <.link
          href={~p"/m/#{@message.id}"}
          class="message-time"
          title={gettext("Permalink to this message")}
        >
          <TopicComponents.time_ago at={@message.opened_at} />
        </.link>
        <span
          :if={@message.deleted_at}
          id={"message-#{@message.id}-deleted"}
          class="badge badge-sm badge-warning"
        >
          {if Messages.deleted_by_author?(@message),
            do: gettext("Deleted by user"),
            else: gettext("Deleted by a moderator")}
        </span>
      </p>
      <blockquote
        :if={@message.reply_to}
        id={"message-#{@message.id}-reply-to"}
        class="message-quote"
      >
        <%= if @message.reply_to.topic_id == @topic.id or
                 MapSet.member?(@viewable_replies, @message.reply_to.id) do %>
          <.link href={~p"/m/#{@message.reply_to.id}"} class="font-medium">
            {gettext("In reply to %{name}", name: @message.reply_to.author.display_name)}
          </.link>
          <span :if={is_nil(@message.reply_to.deleted_at)} class="opacity-70">
            {Forum.excerpt(@message.reply_to)}
          </span>
        <% else %>
          <%!-- TP-15: moved away, to a topic this reader may not view. --%>
          <span class="opacity-70">{gettext("In reply to a message in another thread")}</span>
        <% end %>
        <span :if={@message.reply_to.deleted_at} class="italic opacity-70">
          {if Messages.deleted_by_author?(@message.reply_to),
            do: gettext("Message deleted by user"),
            else: gettext("Message deleted by a moderator")}
        </span>
      </blockquote>
      <.form
        :if={@edit_form}
        for={@edit_form}
        id={"edit-message-#{@message.id}"}
        phx-change="validate_edit"
        phx-submit="save_edit"
        phx-mounted={JS.focus(to: "#edit-message-#{@message.id} textarea")}
      >
        <MessageComponents.editor
          field={@edit_form[:body]}
          label={
            if @mod_edit?,
              do: gettext("Edit this message (Markdown)"),
              else: gettext("Edit your message (Markdown)")
          }
          mode={@editor_mode}
          preview_html={@preview_html}
          upload={@edit_upload}
          image_error={@image_error}
        />
        <.input
          :if={@mod_edit?}
          field={@edit_form[:reason]}
          type="text"
          label={gettext("Reason (shown in the moderation log)")}
          maxlength="500"
        />
        <div class="flex gap-2">
          <.button class="btn btn-primary btn-sm">{gettext("Save")}</.button>
          <button type="button" class="btn btn-sm" phx-click="cancel_edit">
            {gettext("Cancel")}
          </button>
        </div>
      </.form>
      <MessageComponents.collapsible_body
        :if={!@edit_form}
        id={"message-#{@message.id}-body"}
        html={@message.body_html}
      />
      <div :if={@message.edited or @message.scheduled} class="message-meta">
        <span
          :if={@message.scheduled}
          id={"message-#{@message.id}-scheduled"}
          class="message-scheduled"
        >
          {gettext("scheduled message")}
        </span>
        <.versions :if={@message.edited} message={@message} />
      </div>
      <%!-- TP-17: reactions under the message. --%>
      <ReactionComponents.reaction_bar
        message_id={@message.id}
        summary={@reactions}
        viewer={@viewer}
        can_react?={@can_react? and is_nil(@message.deleted_at)}
      />
      <%!-- TP-09: a "Continue topic" button to each topic started from this message (steward
           decision, 2026-10-23); its title is in the name, and on hover. --%>
      <p :if={@forks != []} id={"message-#{@message.id}-forks"} class="message-forks">
        <.link
          :for={fork <- @forks}
          href={~p"/t/#{fork.id}/#{fork.slug}"}
          class="btn btn-xs"
          title={fork.title}
          aria-label={gettext("Continue topic: %{title}", title: fork.title)}
        >
          <.icon name="hero-arrow-turn-down-right-micro" class="size-4" />{gettext("Continue topic")}
        </.link>
      </p>
      <div class="message-actions">
        <ReactionComponents.add_reaction
          :if={@can_react? and is_nil(@message.deleted_at)}
          message_id={@message.id}
        />
        <button
          :if={(@own_closed? or @mod_edit?) and !@edit_form}
          id={"message-#{@message.id}-edit"}
          type="button"
          class="message-action"
          phx-mounted={@refocus == @message.id && JS.focus()}
          phx-click="edit"
          phx-value-id={@message.id}
        >
          <.icon name="hero-pencil-square-micro" class="size-4" />{gettext("Edit")}
        </button>
        <%!-- MO-01: anyone signed in may report someone else's message. --%>
        <.link
          :if={@viewer && @viewer.id != @message.author_id && is_nil(@message.deleted_at)}
          href={~p"/m/#{@message.id}/report"}
          class="message-action"
          id={"message-#{@message.id}-report"}
        >
          <.icon name="hero-flag-micro" class="size-4" />{gettext("Report")}
        </.link>
        <.link
          :if={@can_fork? and is_nil(@message.deleted_at)}
          href={~p"/m/#{@message.id}/new-topic"}
          class="message-action"
          id={"message-#{@message.id}-fork"}
        >
          <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" />{gettext(
            "New topic from this"
          )}
        </.link>
        <.link
          :if={@can_post? and is_nil(@message.deleted_at)}
          href={~p"/t/#{@topic.id}/#{@topic.slug}?reply_to=#{@message.id}" <> "#composer"}
          class="message-action"
          aria-label={gettext("Reply to %{name}", name: @message.author.display_name)}
        >
          <.icon name="hero-arrow-uturn-left-micro" class="size-4" />{gettext("Reply")}
        </.link>
        <%!-- GM-16, MO-02, TP-15: moderator actions, in a card over the page. --%>
        <button
          :if={@can_moderate?}
          type="button"
          id={"message-#{@message.id}-moderate"}
          class="message-action"
          phx-click="open_moderate"
          phx-value-id={@message.id}
        >
          <.icon name="hero-shield-check-micro" class="size-4" />{gettext("Moderate")}
        </button>
      </div>
    </article>
    """
  end

  attr :message, :map, required: true

  # GM-11: a discreet tag that opens every earlier version with its time. A <details> element,
  # so it opens without JavaScript too; its words are the text equivalent (AX-03).
  defp versions(assigns) do
    # Each version was the message's text from the previous change (or the opening) until
    # the edit that replaced it; newest first.
    froms = [assigns.message.opened_at | Enum.map(assigns.message.versions, & &1.created_at)]
    spans = assigns.message.versions |> Enum.zip(froms) |> Enum.reverse()
    assigns = assign(assigns, :spans, spans)

    ~H"""
    <details id={"message-#{@message.id}-versions"} class="message-versions">
      <summary>{gettext("view earlier version")}</summary>
      <ol class="mt-2 space-y-3">
        <li :for={{version, from} <- @spans} class="border-l-2 border-base-300 pl-3">
          <p>
            <time datetime={DateTime.to_iso8601(from)}>
              {Calendar.strftime(from, "%Y-%m-%d %H:%M:%S")}
            </time>
            –
            <time datetime={DateTime.to_iso8601(version.created_at)}>
              {Calendar.strftime(version.created_at, "%Y-%m-%d %H:%M:%S UTC")}
            </time>
          </p>
          <MessageComponents.body html={
            Messages.Body.to_html(version.body_md, Messages.Body.context(@message))
          } />
        </li>
      </ol>
    </details>
    """
  end

  # The start of a text not posted yet, as typed (its Markdown), on one line.
  defp short(body) do
    text = body |> String.split() |> Enum.join(" ")
    if String.length(text) > 140, do: String.slice(text, 0, 140) <> "…", else: text
  end

  attr :schedule, :map, required: true
  attr :error, :string, default: nil

  # `!schedule`: how many hours until the text not sent yet is posted (decimals allowed).
  # The InlineCard hook opens it as a modal dialog and reports its closing.
  defp schedule_dialog(assigns) do
    assigns = assign(assigns, :max, Scheduling.max_hours())

    ~H"""
    <dialog
      id="schedule-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="hide_schedule"
      aria-labelledby="schedule-dialog-title"
    >
      <div class="modal-box schedule-card">
        <h2 id="schedule-dialog-title" class="inline-card-title">
          {gettext("Schedule this message")}
        </h2>
        <p class="schedule-excerpt">{short(@schedule.body)}</p>
        <.form for={%{}} id="schedule-form" phx-submit="schedule">
          <label for="schedule-hours" class="label mb-1">
            {gettext("Post it in how many hours? (at most %{max})", max: @max)}
          </label>
          <input
            id="schedule-hours"
            name="hours"
            type="number"
            inputmode="decimal"
            min="0.01"
            max={@max}
            step="any"
            required
            class="input input-sm w-full"
            aria-describedby={@error && "schedule-error"}
            phx-mounted={JS.focus()}
          />
          <p :if={@error} id="schedule-error" role="alert" class="text-sm text-error mt-1">
            {@error}
          </p>
          <div class="modal-action">
            <button class="btn btn-sm btn-primary">{gettext("Schedule")}</button>
            <button type="button" class="btn btn-sm btn-ghost" phx-click="hide_schedule">
              {gettext("Cancel")}
            </button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end

  attr :mine, :any, required: true
  attr :pending, :list, default: [], doc: "the author's scheduled messages here"
  attr :commands, :list, default: [], doc: "the `!` commands, for the Composer hook"
  attr :reply_to, :any, required: true
  attr :roles, :map, required: true
  attr :author, :map, required: true
  attr :now, DateTime, required: true
  attr :upload, :any, required: true
  attr :image_error, :string, required: true

  # No countdown, button or status around it (GM-07): only the text box. The hook owns its
  # contents (phx-update="ignore"); `data-sent` gives it the open message after a reload.
  # The open state and the time left are hidden text describing the box (AX-03).
  defp composer(assigns) do
    assigns =
      assign(assigns, :left, assigns.mine && DateTime.diff(assigns.mine.closes_at, assigns.now))

    ~H"""
    <section aria-label={gettext("Your message")} class="message message-mine">
      <p :if={@mine} class="message-head"><.author_line author={@author} roles={@roles} /></p>
      <div :if={@reply_to} id="replying-to" class="message-quote">
        <p>
          {gettext("Replying to %{name}:", name: @reply_to.author.display_name)}
          <button type="button" class="link ml-2" phx-click="cancel_reply">
            {gettext("Cancel reply")}
          </button>
        </p>
        <p class="opacity-70">{Forum.excerpt(@reply_to)}</p>
      </div>
      <div
        id="composer"
        class="composer"
        phx-hook="Composer"
        phx-update="ignore"
        data-sent={@mine && @mine.body_md}
        data-commands={Jason.encode!(@commands)}
      >
        <div class="composer-backdrop" aria-hidden="true"></div>
        <textarea
          class="composer-input"
          rows="1"
          aria-label={gettext("Message")}
          aria-describedby="composer-window"
          placeholder={
            gettext("Enter · send | Shift+Enter · new line | Ctrl+Enter or Enter ×3 · new message")
          }
        ></textarea>
        <%!-- TP-10: suggestions while typing @, +, #, / or $, and the commands after !
             (assets/js/suggest.js). --%>
        <ul
          id="composer-suggestions"
          role="listbox"
          class="suggestions"
          aria-label={IdejoWeb.Suggestions.list_label()}
          hidden
        >
        </ul>
      </div>
      <p id="composer-window" class="sr-only">
        <%= cond do %>
          <% is_nil(@mine) -> %>
            {gettext("Enter starts a new message.")}
          <% @left > 0 -> %>
            {gettext("Your message is open.")}
            {ngettext(
              "Ctrl+Enter, or Enter three times, starts a new message in %{count} second.",
              "Ctrl+Enter, or Enter three times, starts a new message in %{count} seconds.",
              @left
            )}
          <% true -> %>
            {gettext("Your message is open.")}
            {gettext("Ctrl+Enter, or Enter three times, starts a new message.")}
        <% end %>
      </p>
      <%!-- TP-12: images pasted or dropped into the composer upload through this input; the
           composer shows no button (GM-07). --%>
      <form :if={@upload} id="composer-image-form" phx-change="validate_image" class="hidden">
        <.live_file_input upload={@upload} />
      </form>
      <p :if={@image_error} role="alert" class="text-sm text-error mt-1">{@image_error}</p>
      <%!-- `!schedule`: what waits to be posted here; only its author sees it. --%>
      <section
        :if={@pending != []}
        id="scheduled-messages"
        aria-labelledby="scheduled-messages-title"
        class="scheduled-messages"
      >
        <h2 id="scheduled-messages-title" class="scheduled-messages-title">
          {gettext("Scheduled")}
        </h2>
        <ul>
          <li :for={scheduled <- @pending} id={"scheduled-#{scheduled.id}"} class="scheduled-item">
            <span class="scheduled-when">
              <time datetime={DateTime.to_iso8601(scheduled.post_at)}>
                {Calendar.strftime(scheduled.post_at, "%Y-%m-%d %H:%M UTC")}
              </time>
            </span>
            <span class="scheduled-text">{short(scheduled.body_md)}</span>
            <button
              type="button"
              class="message-action"
              phx-click="cancel_scheduled"
              phx-value-id={scheduled.id}
              aria-label={
                gettext("Cancel the message scheduled for %{time}",
                  time: Calendar.strftime(scheduled.post_at, "%Y-%m-%d %H:%M UTC")
                )
              }
            >
              {gettext("Cancel")}
            </button>
          </li>
        </ul>
      </section>
    </section>
    """
  end
end
