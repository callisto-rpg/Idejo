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
  sends the whole text on Enter, or with `"break"` on Ctrl+Enter, to `Idejo.Messages.commit/4`
  and keeps it in the box; the reply tells it whether the message closed (GM-05).

  **For assistive technology** (AX-02, AX-03) the open state exists only as text: a hidden
  live region announces each message once when it opens and once when it closes, never at
  appends; open messages read "still being written"; and the composer is described by the
  time left in the author's window, updated every second while it runs.

  **@mentions** (TP-10) link to `/u/{id}`. With JavaScript, the `Mentions` hook turns a click
  on one into `"show_user"`, and the user card opens here in a `<dialog>` (`UserCard` hook)
  instead of leaving the topic; without it, the link opens the card's page.
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Reading
  alias Idejo.Repo
  alias IdejoWeb.Admin
  alias IdejoWeb.ImageUploads
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
           user_card: nil,
           image_error: nil
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
         |> assign(announcement: nil, now: DateTime.utc_now(), tick: nil, user_card: nil)
         |> assign(:reply_to, can_post? && Forum.get_topic_message(topic, session["reply_to_id"]))
         |> put_messages(Forum.list_messages(topic))
         |> put_forks()
         |> ImageUploads.allow(:composer_image, can_post?)
         |> ImageUploads.allow(:edit_image, can_post?)
         |> sync_composer()
         |> schedule_tick()}
    end
  end

  defp user(socket), do: socket.assigns.current_scope && socket.assigns.current_scope.user

  defp subscribe(topic, user) do
    Messages.subscribe(topic.id)
    Access.subscribe_permissions()
    # While this view lives, the user's open message here stays open (GM-12).
    if user, do: Messages.Authors.present(topic.id, user.id)
    # Whatever came between the page and the connection is seen now (TP-07).
    Reading.mark_read(user, topic)
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
  end

  # The role above each author's name (GM-07): their highest-ranked one, with the name colour.
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
      |> Map.new(fn {id, [top | _] = roles} ->
        {id, %{name: Admin.role_name(top), colour: Access.name_colour(roles)}}
      end)

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
        {:noreply, assign(socket, topic: nil, can_post?: false, lost_access?: true, messages: [])}

      topic ->
        {:noreply, assign(socket, topic: topic, can_post?: Forum.can_post?(user(socket), topic))}
    end
  end

  # Someone started a topic from one of these messages (TP-09).
  def handle_info({:forked, _message_id}, socket), do: {:noreply, put_forks(socket)}

  # The grid changed: the viewer may have lost the view or post right since mount.
  def handle_info(:permissions_changed, %{assigns: %{topic: nil}} = socket),
    do: {:noreply, socket}

  def handle_info(:permissions_changed, socket) do
    user = user(socket)

    case Forum.get_viewable_topic(user, socket.assigns.topic.id) do
      nil ->
        Messages.unsubscribe(socket.assigns.topic.id)

        {:noreply, assign(socket, topic: nil, can_post?: false, lost_access?: true, messages: [])}

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

    case Messages.commit(user(socket), topic, body, opts) do
      {:ok, nil} ->
        {:reply, %{closed: false, body: ""}, socket}

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

  # TP-10: a click on an @mention opens that user's card in a dialog.
  def handle_event("show_user", %{"id" => id}, socket) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = user <- Idejo.Accounts.get_user(id) do
      topic = socket.assigns.topic
      return_to = topic && ~p"/t/#{topic.id}/#{topic.slug}"
      card = UserComponents.card_data(user, user(socket), return_to: return_to)
      {:noreply, assign(socket, :user_card, card)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("hide_user", _params, socket), do: {:noreply, assign(socket, :user_card, nil)}

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
      {:ok, _} -> {:noreply, socket}
      _ -> {:noreply, put_flash(socket, :error, gettext("This could not be done."))}
    end
  end

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
    html = Messages.Body.to_html(form.params["body"] || "")
    {:noreply, assign(socket, editor_mode: :preview, preview_html: html)}
  end

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

  # AX-01: the keyboard focus goes back to the message's Edit button, which the editor
  # replaced (it takes the focus when it is mounted again).
  defp close_editor(%{assigns: %{editing: {id, _}}} = socket),
    do: assign(socket, editing: nil, refocus: id)

  defp close_editor(socket), do: assign(socket, :editing, nil)

  @impl true
  def render(assigns) do
    mine = open_message(assigns.messages, assigns.current_scope && assigns.current_scope.user)
    {before, after_} = split(assigns.messages, mine)
    # TP-12: allowed at mount for those who could post then; nil otherwise.
    uploads = assigns[:uploads] || %{}

    assigns =
      assign(assigns,
        before: before,
        mine: mine,
        later: after_,
        deleted_runs: Map.merge(deleted_runs(before), deleted_runs(after_)),
        composer_upload: uploads[:composer_image],
        edit_upload: uploads[:edit_image]
      )

    ~H"""
    <div id="topic-live" phx-hook="Mentions">
      <dialog
        :if={@user_card}
        id="user-card"
        class="modal"
        phx-hook="UserCard"
        aria-labelledby="user-card-name"
      >
        <div class="modal-box">
          <UserComponents.user_card card={@user_card} />
          <div class="modal-action">
            <button type="button" class="btn btn-sm" phx-click="hide_user">
              {gettext("Close")}
            </button>
          </div>
        </div>
      </dialog>
      <%!-- AX-02: read out when a message opens or closes; the list itself is not live. --%>
      <div id="topic-announcer" role="status" aria-live="polite" aria-atomic="true" class="sr-only">
        <span :if={@announcement} id={"announcement-#{elem(@announcement, 0)}"}>
          {elem(@announcement, 1)}
        </span>
      </div>
      <p :if={@lost_access?} id="topic-gone" role="status" class="opacity-70">
        {gettext("You can no longer view this topic.")}
      </p>

      <ol id="messages" class="message-list">
        <li
          :for={message <- @before}
          :key={message.id}
          id={"message-#{message.id}"}
          hidden={@deleted_runs[message.id] == :rest and !@can_moderate?}
        >
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
          />
        </li>
        <li :if={@can_post?} id={if @mine, do: "message-#{@mine.id}", else: "composer-slot"}>
          <.composer
            mine={@mine}
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
          />
        </li>
      </ol>

      <p :if={@flash["error"]} role="alert" class="alert alert-error mt-4">{@flash["error"]}</p>

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

  # MO-02: for readers, a run of deleted messages shows as one line. Maps each deleted
  # message's id to `{:first, count}` for the first of its run, `:rest` for the others.
  defp deleted_runs(messages) do
    messages
    |> Enum.chunk_by(&(&1.deleted_at != nil))
    |> Enum.filter(fn [first | _] -> first.deleted_at != nil end)
    |> Enum.flat_map(fn [first | rest] = run ->
      [{first.id, {:first, length(run)}} | Enum.map(rest, &{&1.id, :rest})]
    end)
    |> Map.new()
  end

  defp deleted_text({:first, count}),
    do:
      ngettext(
        "Message deleted by a moderator",
        "%{count} messages deleted by a moderator",
        count
      )

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
      <span class="font-semibold">{@author.display_name}</span>
      <span :if={@role} class="author-role">
        <Admin.swatch colour={@role.colour} />
        {@role.name}
      </span>
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
      :if={@message.deleted_at && !@can_moderate? && match?({:first, _}, @deleted_run)}
      id={"message-#{@message.id}-deleted"}
      class="message-deleted"
    >
      {deleted_text(@deleted_run)}
    </p>
    <article
      :if={is_nil(@message.deleted_at) or @can_moderate?}
      aria-labelledby={"message-#{@message.id}-author"}
      class="message"
    >
      <p id={"message-#{@message.id}-author"} class="message-head">
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
          {gettext("Deleted by a moderator")}
        </span>
      </p>
      <blockquote
        :if={@message.reply_to}
        id={"message-#{@message.id}-reply-to"}
        class="message-quote"
      >
        <.link href={~p"/m/#{@message.reply_to.id}"} class="font-medium">
          {gettext("In reply to %{name}", name: @message.reply_to.author.display_name)}
        </.link>
        <span :if={is_nil(@message.reply_to.deleted_at)} class="opacity-70">
          {Forum.excerpt(@message.reply_to)}
        </span>
        <span :if={@message.reply_to.deleted_at} class="italic opacity-70">
          {gettext("Message deleted by a moderator")}
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
      <.versions :if={@message.edited} message={@message} />
      <%!-- TP-09: a discreet link to each topic started from this message. --%>
      <p :if={@forks != []} id={"message-#{@message.id}-forks"} class="message-forks">
        {gettext("Continued in")}
        <%= for {fork, i} <- Enum.with_index(@forks) do %>
          <span :if={i > 0}>, </span><.link href={~p"/t/#{fork.id}/#{fork.slug}"} class="link">{fork.title}</.link>
        <% end %>
      </p>
      <div class="message-actions">
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
        <%!-- GM-16, MO-02: moderator actions, each with an optional reason for the log (MO-03). --%>
        <details
          :if={@can_moderate? and is_nil(@message.deleted_at) and @viewer.id != @message.author_id}
          id={"message-#{@message.id}-moderate"}
          class="message-moderate"
        >
          <summary class="message-action">
            <.icon name="hero-shield-check-micro" class="size-4" />{gettext("Moderate")}
          </summary>
          <form
            phx-submit="moderate_message"
            id={"message-#{@message.id}-moderate-form"}
            class="mt-2 flex flex-wrap items-end gap-2"
          >
            <input type="hidden" name="message_id" value={@message.id} />
            <label class="grow">
              <span class="label mb-1">{gettext("Reason (shown in the moderation log)")}</span>
              <input type="text" name="reason" maxlength="500" class="input input-sm w-full" />
            </label>
            <button
              :if={@message.state == "open"}
              name="do"
              value="close"
              class="btn btn-sm"
              data-confirm={gettext("Close this message? Its author will start a new one.")}
            >
              {gettext("Close message")}
            </button>
            <button
              name="do"
              value="delete"
              class="btn btn-sm btn-error"
              data-confirm={
                gettext("Delete this message? Readers will see that a moderator deleted it.")
              }
            >
              {gettext("Delete message")}
            </button>
          </form>
        </details>
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
          <MessageComponents.body html={Messages.Body.to_html(version.body_md)} />
        </li>
      </ol>
    </details>
    """
  end

  attr :mine, :any, required: true
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
      >
        <div class="composer-backdrop" aria-hidden="true"></div>
        <textarea
          class="composer-input"
          rows="1"
          aria-label={gettext("Message")}
          aria-describedby="composer-window"
          placeholder={
            gettext("Type here · Enter send · Shift+Enter line break · Ctrl+Enter new line")
          }
        ></textarea>
      </div>
      <p id="composer-window" class="sr-only">
        <%= cond do %>
          <% is_nil(@mine) -> %>
            {gettext("Enter starts a new message.")}
          <% @left > 0 -> %>
            {gettext("Your message is open.")}
            {ngettext(
              "Ctrl+Enter starts a new message in %{count} second.",
              "Ctrl+Enter starts a new message in %{count} seconds.",
              @left
            )}
          <% true -> %>
            {gettext("Your message is open.")}
            {gettext("Ctrl+Enter starts a new message.")}
        <% end %>
      </p>
      <%!-- TP-12: images pasted or dropped into the composer upload through this input; the
           composer shows no button (GM-07). --%>
      <form :if={@upload} id="composer-image-form" phx-change="validate_image" class="hidden">
        <.live_file_input upload={@upload} />
      </form>
      <p :if={@image_error} role="alert" class="text-sm text-error mt-1">{@image_error}</p>
    </section>
    """
  end
end
