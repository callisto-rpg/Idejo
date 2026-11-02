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
  alias Idejo.Forum.TopicWindow
  alias Idejo.Messages
  alias Idejo.Messages.{Automessages, Polls, Scheduling}
  alias Idejo.Reading
  alias Idejo.Repo
  alias IdejoWeb.Admin
  alias IdejoWeb.ImageUploads
  alias IdejoWeb.MessageModerationComponents
  alias IdejoWeb.PollComponents
  alias IdejoWeb.ReactionComponents
  alias IdejoWeb.UserComponents

  on_mount {IdejoWeb.UserAuth, :mount_current_scope}

  # How long a completed message's head says "sent & committed" (steward decision, 2026-10-31).
  @committed_ms 3000

  # The window of a view with nothing to show: no topic, or one the viewer may no longer view
  # (Long topics, `put_window/2`).
  @no_window [
    messages: [],
    nav: nil,
    deleted_runs: %{},
    gap: false,
    earlier_count: 0,
    later_count: 0,
    at_end?: true,
    new_below: 0,
    page_before: nil,
    page_after: nil,
    last_page: 1,
    opening_id: nil,
    latest: nil,
    mine_last: nil,
    rest_pos: 0,
    total: 0,
    own_open: nil
  ]

  @impl true
  # The viewer's roles, the settings and permission checks are read once for the whole mount
  # (Idejo.Memo; in the page's request it is on already); later events read them afresh.
  def mount(params, session, socket),
    do: Idejo.Memo.run(fn -> do_mount(params, session, socket) end)

  defp do_mount(_params, %{"topic_id" => topic_id} = session, socket) do
    user = user(socket)

    # A private conversation too, for its participants (steward decision, 2026-10-27).
    case Forum.get_readable_topic(user, topic_id) do
      nil ->
        {:ok,
         socket
         |> assign(@no_window)
         |> assign(
           topic: nil,
           can_post?: false,
           lost_access?: false,
           roles: %{},
           committed: nil,
           read_timer: nil,
           editing: nil,
           refocus: nil,
           can_moderate?: false,
           announcement: nil,
           now: DateTime.utc_now(),
           tick: nil,
           forks: %{},
           can_fork?: false,
           automessages: [],
           card: nil,
           image_error: nil,
           reactions: %{},
           can_react?: false,
           picker: nil,
           reaction_who: nil,
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
           mention_glows: %{},
           mention_tags: [],
           pending: [],
           schedule: nil,
           polls: %{},
           poll_form: nil,
           live?: connected?(socket),
           revealed: MapSet.new(),
           draft_over: nil,
           early_reply?: true,
           punctuate?: true,
           too_soon?: false,
           composing_edit: nil,
           edit_versioned?: false,
           images?: false
         )}

      topic ->
        # First subscribe, then load: a message posted in between arrives as an event.
        if connected?(socket), do: subscribe(topic, user)

        can_post? = Forum.can_post?(user, topic)

        {:ok,
         socket
         |> assign(topic: topic, can_post?: can_post?, lost_access?: false, roles: %{})
         |> assign(committed: nil, read_timer: nil)
         |> assign(:can_moderate?, user != nil and Access.can?(user, :moderate, topic.category))
         |> assign(:can_fork?, can_fork?(user, topic))
         |> assign(:automessages, automessages(user, topic))
         |> assign(editing: nil, refocus: nil, editor_mode: :write, preview_html: "")
         |> assign(announcement: nil, now: DateTime.utc_now(), tick: nil, card: nil)
         |> assign(:unanswered_minutes, Idejo.Settings.get(:gm_unanswered_minutes))
         |> assign(:reply_to, can_post? && Forum.get_topic_message(topic, session["reply_to_id"]))
         |> assign(early_reply?: Idejo.Settings.get(:gm_early_reply), too_soon?: false)
         |> assign(:punctuate?, user == nil or user.auto_punctuation)
         |> assign(composing_edit: nil, edit_versioned?: false)
         |> assign(sizes: TopicWindow.sizes(), new_below: 0)
         |> assign(:mine_last, TopicWindow.last_by(topic, user))
         |> assign(:own_open, open_id(can_post? && user, topic))
         |> put_window(landing(session))
         |> put_poster_role()
         |> put_draft()
         |> put_first_unread(session["first_unread"])
         |> put_mention_glows()
         |> put_forks()
         |> assign(can_react?: can_react?(user, topic), picker: nil, reaction_who: nil)
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
         |> put_polls()
         |> assign(schedule: nil, schedule_error: nil, poll_form: nil)
         |> assign(live?: connected?(socket), revealed: MapSet.new())
         |> put_pending()
         # TP-12: `@uploads` exists only when they were allowed here, at mount.
         |> assign(:images?, can_post?)
         |> ImageUploads.allow(:composer_image, can_post?)
         |> ImageUploads.allow(:edit_image, can_post?)
         |> sync_composer()
         |> schedule_tick()}
    end
  end

  defp user(socket), do: socket.assigns.current_scope && socket.assigns.current_scope.user

  # TP-09: never from a private conversation (steward decision, 2026-10-27), whose words
  # would leave it.
  # The automessages the viewer may send there (steward decisions, 2026-11-01).
  defp automessages(user, topic), do: Automessages.commands_for(user, topic)

  defp can_fork?(_user, %{private: true}), do: false
  defp can_fork?(user, _topic), do: Forum.list_startable_categories(user) != []

  # Reply starts a new message (steward decision, 2026-10-24): with the author's message
  # still open, the composer leaves it for a new one at the end; `draft_over` is the open
  # message it left. Sending closes that message first (`Messages.commit/4` with `new:`).
  # Without the reply, or with replies waiting for the timer (`gm_early_reply` off), Enter is
  # refused until Ctrl+Enter could start a new message.
  defp put_draft(socket) do
    open = socket.assigns.reply_to && open_message(socket.assigns.messages, user(socket))
    assign(socket, :draft_over, open && open.id)
  end

  # The open message the composer left, while it is still open.
  defp draft_over(%{draft_over: nil}), do: nil

  defp draft_over(%{draft_over: id, messages: messages}),
    do: Enum.find(messages, &(&1.id == id and &1.state == "open"))

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

  # Unread messages that @mention the reader or +mention one of their roles (steward
  # decision, 2026-10-25): the `MentionGlow` hook makes each glow once it is scrolled to, in
  # its notification dot's colour, and the tag naming the reader pulse. Read from the stored
  # HTML's links (`/u/{id}`, `/r/{slug}`), with no query but the reader's roles.
  defp put_mention_glows(%{assigns: %{first_unread: %{id: first_id}}} = socket) do
    user = user(socket)

    roles =
      for role <- Access.roles_of(user),
          not (role.built_in and role.name in ~w(member guest)),
          do: "/r/" <> Access.role_slug(role)

    mention = "/u/" <> user.id

    glows =
      socket.assigns.messages
      |> Enum.drop_while(&(&1.id != first_id))
      |> Enum.filter(&(&1.author_id != user.id and is_nil(&1.deleted_at)))
      |> Enum.flat_map(fn message ->
        cond do
          links_to?(message.body_html, [mention]) -> [{message.id, "mention"}]
          links_to?(message.body_html, roles) -> [{message.id, "role-mention"}]
          true -> []
        end
      end)
      |> Map.new()

    assign(socket, mention_glows: glows, mention_tags: [mention | roles])
  end

  defp put_mention_glows(socket), do: assign(socket, mention_glows: %{}, mention_tags: [])

  defp links_to?(html, hrefs), do: Enum.any?(hrefs, &String.contains?(html, ~s(href="#{&1}")))

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

  # Who reacted to a message, for the list or its card; nothing left closes it.
  defp put_reaction_who(socket, who) do
    case Idejo.Reactions.reactors(who.message_id) do
      [] -> assign(socket, :reaction_who, nil)
      people -> assign(socket, :reaction_who, Map.put(who, :people, people))
    end
  end

  # TP-17: the reactions of every message shown, in one query; later changes come as events.
  defp put_reactions(socket) do
    ids = Enum.map(socket.assigns.messages, & &1.id)
    assign(socket, :reactions, Idejo.Reactions.summaries(ids))
  end

  # `!poll`: the polls under the messages shown, in one query; later changes come as events.
  defp put_polls(socket) do
    ids = Enum.map(socket.assigns.messages, & &1.id)
    assign(socket, :polls, Polls.summaries(ids))
  end

  # TP-09: each message's "continued in" topics that the viewer may see.
  defp put_forks(socket) do
    ids = Enum.map(socket.assigns.messages, & &1.id)
    assign(socket, :forks, Forum.list_forks(user(socket), ids))
  end

  # Long topics, a window at a time (steward decision, 2026-11-01). Never every message of
  # the topic: its opening message, pinned on top (not in a private conversation, which has
  # none), and a run of messages in order, from place `rest_pos` (from 0) of the topic's
  # `total`. Earlier and later ones load as the reader scrolls (`load_earlier`,
  # `load_later`), at most `sizes.cap` at once besides the messages kept for the viewer
  # (`kept_ids/1`). `messages` holds them all, the opening first, so a loaded message is found
  # as before. How many: the "Performance" setting (`Idejo.Forum.TopicWindow.sizes/1`).

  # Where the reader lands: a page asked for (`?page=n`, the links without JavaScript), a
  # message (`?around=`, permalinks and notifications), the composer after "Reply" without
  # JavaScript, their first unread message, else the end, where the conversation goes on.
  defp landing(session) do
    window = session["window"] || %{}

    cond do
      page = positive_integer(window["page"]) -> {:page, page}
      is_binary(window["around"]) -> {:around, window["around"]}
      is_binary(session["reply_to_id"]) -> :end
      match?(%{id: _}, session["first_unread"]) -> {:around, session["first_unread"].id}
      true -> :end
    end
  end

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp put_window(socket, spec) do
    %{topic: topic, sizes: sizes} = socket.assigns
    total = TopicWindow.count(topic)
    {loaded, pos} = load_window(topic, spec, sizes, total, socket.assigns.own_open)
    set_window(socket, loaded, pos, total)
  end

  # The messages `spec` asks for, in order, with the place of the first.
  defp load_window(topic, {:page, page}, %{page: size}, total, _open_id) do
    page = min(page, TopicWindow.page_of(max(total - 1, 0), size))
    {TopicWindow.page(topic, page, size), (page - 1) * size}
  end

  defp load_window(topic, {:around, id}, sizes, total, open_id) do
    case Forum.get_topic_message(topic, id) do
      nil ->
        load_window(topic, :end, sizes, total, open_id)

      message ->
        loaded = TopicWindow.around(topic, message, sizes.before, sizes.after)
        index = Enum.find_index(loaded, &(&1.id == message.id))
        {loaded, TopicWindow.position(topic, message) - index}
    end
  end

  # The end, back to the viewer's open message when it is older: the composer is that message
  # (GM-02), so it is always loaded with it.
  defp load_window(topic, :end, sizes, total, open_id) do
    loaded = TopicWindow.last(topic, sizes.before + sizes.after)

    with id when is_binary(id) <- open_id,
         false <- Enum.any?(loaded, &(&1.id == id)),
         %Messages.Message{} = open <- Forum.get_topic_message(topic, id) do
      {TopicWindow.since(topic, open), TopicWindow.position(topic, open)}
    else
      _ -> {loaded, total - length(loaded)}
    end
  end

  # The opening message pinned first, then the run (alone in a private conversation).
  # A message posted between the count and the load can make a run start at the opening
  # message while `pos` says it does not: it is the start, or the opening message would be
  # shown twice (the same key twice, which crashes the render). The count is never below
  # what was loaded.
  defp set_window(socket, loaded, pos, total) do
    {pinned, rest, rest_pos} =
      cond do
        socket.assigns.topic.private or loaded == [] ->
          {nil, loaded, max(pos, 0)}

        pos <= 0 ->
          {hd(loaded), tl(loaded), 1}

        true ->
          case {opening(socket), loaded} do
            {%{id: id} = first, [%{id: id} | rest]} -> {first, rest, 1}
            {first, _loaded} -> {first, loaded, pos}
          end
      end

    total = max(total, rest_pos + length(rest))

    socket
    |> assign(rest_pos: rest_pos, total: total)
    |> assign(:opening_id, opening_id(socket, pinned, loaded, pos))
    |> put_messages(List.wrap(pinned) ++ rest)
    |> put_bounds()
  end

  # The opening message, from the messages loaded when it is among them.
  defp opening(socket) do
    case socket.assigns do
      %{messages: [%{id: id} = first | _], opening_id: id} -> first
      _ -> TopicWindow.first(socket.assigns.topic)
    end
  end

  defp opening_id(_socket, %{id: id}, _loaded, _pos), do: id
  defp opening_id(_socket, nil, [first | _], 0), do: first.id

  defp opening_id(socket, nil, _loaded, _pos) do
    case socket.assigns[:opening_id] || TopicWindow.first(socket.assigns.topic) do
      %{id: id} -> id
      id -> id
    end
  end

  # The pinned opening message (nil in a private conversation) and the run after it.
  defp parts(%{topic: %{private: true}, messages: messages}), do: {nil, messages}
  defp parts(%{messages: []}), do: {nil, []}
  defp parts(%{messages: [pinned | rest]}), do: {pinned, rest}

  # How many messages are not loaded before and after the run, the pages that hold them for
  # the links without JavaScript, and the navigator's links: the opening message, the topic's
  # latest (`latest`, kept current by new messages) and the viewer's own last one.
  defp put_bounds(socket) do
    %{messages: messages, rest_pos: rest_pos, total: total, sizes: %{page: size}} =
      socket.assigns

    {pinned, rest} = parts(socket.assigns)
    earlier = if pinned, do: max(rest_pos - 1, 0), else: rest_pos
    later = max(total - rest_pos - length(rest), 0)

    latest =
      cond do
        later == 0 -> latest_of(List.last(messages))
        socket.assigns[:latest] -> socket.assigns.latest
        true -> TopicWindow.latest(socket.assigns.topic)
      end

    socket
    |> assign(
      gap: pinned != nil and earlier > 0,
      earlier_count: earlier,
      later_count: later,
      at_end?: later == 0,
      new_below: if(later == 0, do: 0, else: socket.assigns.new_below),
      latest: latest,
      page_before: earlier > 0 && TopicWindow.page_of(rest_pos - 1, size),
      page_after: later > 0 && TopicWindow.page_of(rest_pos + length(rest), size),
      last_page: TopicWindow.page_of(max(total - 1, 0), size)
    )
    |> put_nav()
  end

  defp put_nav(%{assigns: %{opening_id: nil}} = socket), do: assign(socket, :nav, nil)

  defp put_nav(socket) do
    %{opening_id: first, latest: latest, mine_last: mine} = socket.assigns
    assign(socket, :nav, %{first: first, last: latest && latest.id, mine: mine})
  end

  defp latest_of(nil), do: nil
  defp latest_of(message), do: %{id: message.id, opened_at: message.opened_at}

  # The loaded messages, changed: their authors' roles, quotes from other topics, the runs of
  # deleted messages.
  defp put_messages(socket, messages) do
    socket
    |> assign(:messages, messages)
    |> add_roles(messages)
    |> put_viewable_replies(messages)
    |> put_derived()
  end

  # One loaded message new or changed (NF-01): only it is looked at, for its author's role
  # when new to this view and its quote when that leads to another topic, so most events cost
  # no query; the rest is worked out from the messages in memory.
  defp put_message(socket, message) do
    socket
    |> assign(:messages, upsert(socket.assigns.messages, message))
    |> add_roles([message])
    |> add_viewable_reply(message)
    |> put_derived()
  end

  # What the page draws from the loaded list, worked out once per change of it rather than
  # at each render: the runs of deleted messages, counted apart for an opening message pinned
  # away from the run.
  defp put_derived(socket) do
    runs =
      case parts(socket.assigns) do
        {pinned, rest} when pinned != nil and rest != [] ->
          if socket.assigns.rest_pos > 1,
            do: Map.merge(deleted_runs([pinned]), deleted_runs(rest)),
            else: deleted_runs(socket.assigns.messages)

        _ ->
          deleted_runs(socket.assigns.messages)
      end

    assign(socket, :deleted_runs, runs)
  end

  # More messages: before the run, or after it. Loading earlier drops the latest ones past
  # the cap, unless the run reaches the end and the viewer may write (the composer is there,
  # with what they typed and did not send); loading later drops the earliest ones past it.
  defp load_more(socket, :earlier) do
    %{topic: topic, sizes: %{step: step}, earlier_count: earlier, rest_pos: rest_pos} =
      socket.assigns

    {pinned, rest} = parts(socket.assigns)
    older = TopicWindow.before(topic, hd(rest), min(step, earlier))

    socket
    |> assign(:rest_pos, rest_pos - length(older))
    |> put_messages(List.wrap(pinned) ++ older ++ rest)
    |> put_bounds()
    |> then(&if(&1.assigns.at_end? and &1.assigns.can_post?, do: &1, else: trim(&1, :latest)))
  end

  defp load_more(socket, :later) do
    %{topic: topic, sizes: %{step: step}, later_count: later} = socket.assigns
    {pinned, rest} = parts(socket.assigns)
    newer = TopicWindow.next(topic, List.last(rest) || pinned, min(step, later))

    socket
    |> put_messages(List.wrap(pinned) ++ rest ++ newer)
    |> put_bounds()
    |> trim(:earliest)
  end

  # At most `sizes.cap` messages in the run, besides what is kept for the viewer. Never the
  # earliest while the composer edits the opening message: it stays in the run with it.
  defp trim(%{assigns: %{composing_edit: id, opening_id: id}} = socket, :earliest)
       when is_binary(id),
       do: socket

  defp trim(socket, side) do
    {pinned, rest} = parts(socket.assigns)
    excess = length(rest) - socket.assigns.sizes.cap
    kept = kept_ids(socket.assigns)

    if excess > 0, do: drop(socket, side, pinned, rest, excess, kept), else: socket
  end

  defp drop(socket, :earliest, pinned, rest, excess, kept) do
    # Up to the first message kept, never past it.
    keep_from = Enum.find_index(rest, &MapSet.member?(kept, &1.id)) || excess
    dropped = min(excess, keep_from)

    socket
    |> assign(:rest_pos, socket.assigns.rest_pos + dropped)
    |> put_messages(List.wrap(pinned) ++ Enum.drop(rest, dropped))
    |> put_bounds()
  end

  defp drop(socket, :latest, pinned, rest, excess, kept) do
    last_kept =
      rest
      |> Enum.with_index()
      |> Enum.filter(&MapSet.member?(kept, elem(&1, 0).id))
      |> List.last()

    room = if last_kept, do: length(rest) - elem(last_kept, 1) - 1, else: excess
    dropped = min(excess, room)

    socket
    |> put_messages(List.wrap(pinned) ++ Enum.drop(rest, -dropped))
    |> put_bounds()
  end

  # Messages the viewer is working on, never dropped from the window: their open message and
  # what the composer, the editor, the moderation card or the delete dialog has open.
  defp kept_ids(assigns) do
    editing = with {id, _form} <- assigns.editing, do: id

    [
      assigns.own_open,
      assigns.composing_edit,
      editing,
      assigns.moderating,
      assigns.confirm_delete
    ]
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  # What the window's messages carry, for the messages it holds now.
  defp refresh_window_data(socket) do
    socket |> put_forks() |> put_reactions() |> put_polls() |> put_mention_glows()
  end

  # The end of the topic, where the composer is: everything up to it is read now (TP-07).
  defp to_end(socket) do
    Reading.mark_read(user(socket), socket.assigns.topic)
    socket |> put_window(:end) |> refresh_window_data()
  end

  # TP-15: a reply may lead to another topic after a move; its quote shows only to readers who
  # may view that topic. Messages of this topic need no query (NF-01).
  defp put_viewable_replies(socket, messages) do
    assign(
      socket,
      :viewable_replies,
      Forum.viewable_message_ids(user(socket), foreign_replies(socket, messages))
    )
  end

  # The same for one message: a query only when its quote leads to another topic.
  defp add_viewable_reply(socket, message) do
    case foreign_replies(socket, [message]) do
      [] ->
        socket

      [id] ->
        viewable = socket.assigns.viewable_replies

        if MapSet.member?(Forum.viewable_message_ids(user(socket), [id]), id),
          do: assign(socket, :viewable_replies, MapSet.put(viewable, id)),
          else: assign(socket, :viewable_replies, MapSet.delete(viewable, id))
    end
  end

  defp foreign_replies(socket, messages) do
    topic_id = socket.assigns.topic.id

    for %{reply_to: %Messages.Message{topic_id: other} = reply} <- messages,
        other != topic_id,
        do: reply.id
  end

  # The role next to each author's name (GM-07): their highest-ranked one that is "Visible
  # next to name" (steward decision, 2026-10-23), or none.
  # Only authors not seen yet are looked up, so most events cost no query (NF-01).
  # A broadcast message carries its author's role (`author_role`, NF-04): no query then.
  defp add_roles(socket, messages) do
    {known, rest} =
      messages
      |> Enum.reject(&Map.has_key?(socket.assigns.roles, &1.author_id))
      |> Enum.uniq_by(& &1.author_id)
      |> Enum.split_with(&(&1.author_role != :unknown))

    socket =
      if known == [],
        do: socket,
        else:
          assign(
            socket,
            :roles,
            Enum.reduce(known, socket.assigns.roles, &Map.put(&2, &1.author_id, &1.author_role))
          )

    if rest == [], do: socket, else: assign_roles(socket, Enum.map(rest, & &1.author))
  end

  # The composer shows its author's name before their first message here (no jump on the
  # first Enter, steward report, 2026-10-31), so their role is needed at mount.
  defp put_poster_role(%{assigns: %{can_post?: true, roles: roles}} = socket) do
    user = user(socket)
    if Map.has_key?(roles, user.id), do: socket, else: assign_roles(socket, [user])
  end

  defp put_poster_role(socket), do: socket

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
          %{id: id} when id == socket.assigns.draft_over -> ""
          %{body_md: body} -> body
          nil -> ""
        end

      push_event(socket, "composer_sent", %{body: body})
    else
      socket
    end
  end

  defp sync_composer(socket), do: socket

  # TP-07: a new message arriving while the end is shown is read (steward decision), marked
  # a moment later, once for all that came meanwhile, and at a moment of its own for each
  # view (NF-04): 200 viewers marking each of 30 messages opened within seconds ran the
  # database pool dry. `:read_mark_ms` is the wait and its spread; 0 marks at once.
  defp mark_read_soon(%{assigns: %{read_timer: ref}} = socket) when ref != nil, do: socket

  defp mark_read_soon(socket) do
    case Application.get_env(:idejo, :read_mark_ms, {2_000, 2_000}) do
      {0, _spread} ->
        Reading.mark_read(user(socket), socket.assigns.topic)
        socket

      {wait, spread} ->
        assign(
          socket,
          :read_timer,
          Process.send_after(self(), :mark_read, wait + :rand.uniform(spread))
        )
    end
  end

  defp open_message(_messages, nil), do: nil

  defp open_message(messages, user),
    do: Enum.find(messages, &(&1.state == "open" and &1.author_id == user.id))

  @impl true
  def handle_info({:message, message}, socket) do
    # Loaded once by the broadcast (NF-01); this costs nothing then.
    message = Repo.preload(message, Messages.shown())
    old = Enum.find(socket.assigns.messages, &(&1.id == message.id))

    cond do
      old ->
        {:noreply,
         socket
         |> track_mine(message)
         |> announce(old, message)
         |> put_message(message)
         |> schedule_tick()}

      # The window reaches the end: a new message joins it (in its place, should the events
      # of two messages arrive out of order).
      socket.assigns.at_end? and within_run?(socket.assigns, message) ->
        # A message that arrives while the topic is open is read (TP-07).
        {:noreply,
         socket
         |> mark_read_soon()
         |> arrived(message)
         |> put_message(message)
         |> put_bounds()
         |> trim(:earliest)
         |> schedule_tick()}

      # The reader is further up: they are told how many came, and go there with
      # `jump_to_end` (steward decision, 2026-11-01).
      newer?(message, socket.assigns.latest) ->
        {:noreply,
         socket
         |> arrived(message)
         |> assign(:new_below, socket.assigns.new_below + 1)
         |> put_bounds()}

      # An earlier message the window does not hold changed: nothing here shows it (the
      # viewer's own open message closing is noted).
      true ->
        {:noreply, track_mine(socket, message)}
    end
  end

  # The read mark a new message asked for (`mark_read_soon/1`), while the end is still shown.
  def handle_info(:mark_read, socket) do
    if socket.assigns.at_end?, do: Reading.mark_read(user(socket), socket.assigns.topic)
    {:noreply, assign(socket, :read_timer, nil)}
  end

  def handle_info({:committed_shown, id}, %{assigns: %{committed: id}} = socket),
    do: {:noreply, assign(socket, :committed, nil)}

  def handle_info({:committed_shown, _id}, socket), do: {:noreply, socket}

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
    case Forum.get_readable_topic(user(socket), topic_id) do
      nil ->
        Messages.unsubscribe(topic_id)

        {:noreply,
         socket
         |> assign(@no_window)
         |> assign(
           topic: nil,
           can_post?: false,
           can_react?: false,
           lost_access?: true,
           reaction_who: nil
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
  # An open list of who reacted is read again; only this viewer's, who has it open.
  def handle_info({:reactions, message_id, summary}, socket) do
    socket = assign(socket, :reactions, Map.put(socket.assigns.reactions, message_id, summary))

    case socket.assigns.reaction_who do
      %{message_id: ^message_id} = who -> {:noreply, put_reaction_who(socket, who)}
      _ -> {:noreply, socket}
    end
  end

  # `!poll`: someone voted, or a poll was added or closed; worked out once (NF-01).
  def handle_info({:poll, message_id, summary}, socket),
    do:
      {:noreply,
       assign(socket,
         polls: Map.put(socket.assigns.polls, message_id, summary),
         now: DateTime.utc_now()
       )}

  # TP-15: messages moved into or out of this topic: read it again.
  def handle_info({:messages_moved, _topic_id}, %{assigns: %{topic: nil}} = socket),
    do: {:noreply, socket}

  def handle_info({:messages_moved, topic_id}, socket) do
    case Forum.get_viewable_topic(user(socket), topic_id) do
      nil ->
        {:noreply, socket}

      topic ->
        # Read again where the reader is: the end, or around the first message they had.
        spec =
          case parts(socket.assigns) do
            _ when socket.assigns.at_end? -> :end
            {_pinned, [first | _]} -> {:around, first.id}
            _ -> :end
          end

        socket =
          socket
          |> assign(topic: topic, latest: nil)
          |> assign(:mine_last, TopicWindow.last_by(topic, user(socket)))
          |> put_window(spec)

        ids = MapSet.new(socket.assigns.messages, & &1.id)
        selected = socket.assigns.selected && MapSet.intersection(socket.assigns.selected, ids)

        {:noreply,
         socket
         |> assign(:selected, selected)
         |> refresh_window_data()
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

    case Forum.get_readable_topic(user, socket.assigns.topic.id) do
      nil ->
        Messages.unsubscribe(socket.assigns.topic.id)

        {:noreply,
         socket
         |> assign(@no_window)
         |> assign(
           topic: nil,
           can_post?: false,
           can_react?: false,
           lost_access?: true,
           reaction_who: nil
         )}

      topic ->
        {:noreply,
         socket
         |> assign(
           can_post?: Forum.can_post?(user, topic),
           can_moderate?: user != nil and Access.can?(user, :moderate, topic.category),
           can_fork?: can_fork?(user, topic),
           automessages: automessages(user, topic)
         )
         |> put_viewable_replies(socket.assigns.messages)
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

  # What a command sends for (steward decision, 2026-10-23): `!new-topic` goes on to the new
  # topic; `!poll` and `!spoiler` act on the message just sent.
  defp after_send(socket, "new_topic", message, _params), do: new_topic_from(socket, message)

  defp after_send(socket, "poll", message, _params),
    do: socket |> assign(:reply_to, nil) |> open_poll(message)

  defp after_send(socket, "spoiler", message, params),
    do: socket |> assign(:reply_to, nil) |> toggle_spoiler(message, params["label"])

  defp after_send(socket, _then, _message, _params), do: assign(socket, :reply_to, nil)

  # The message a commit completed: this one (Ctrl+Enter), or the open one a new message
  # closed (after Reply).
  defp completed(_socket, %{state: "closed", id: id}, _opts), do: id
  defp completed(socket, _message, opts), do: opts[:new] && socket.assigns.draft_over

  # The author's message just completed: its head says "sent & committed" for
  # `@committed_ms`, then shows the role (steward decision, 2026-10-31).
  defp put_committed(socket, id) when id in [nil, false], do: socket

  defp put_committed(socket, id) do
    Process.send_after(self(), {:committed_shown, id}, @committed_ms)
    assign(socket, :committed, id)
  end

  # `!poll`: the dialog for a poll under the author's message, one per message; with no
  # message, the poll is posted as one.
  defp open_poll(socket, nil),
    do: assign(socket, :poll_form, %{message_id: nil, params: %{}, count: 2, error: nil})

  defp open_poll(socket, message) do
    if Map.has_key?(socket.assigns.polls, message.id) or Polls.summary(message.id) != nil,
      do: put_flash(socket, :error, gettext("This message has a poll already.")),
      else:
        assign(socket, :poll_form, %{message_id: message.id, params: %{}, count: 2, error: nil})
  end

  # Under the author's message, or with none, posted as a message of its own.
  defp add_poll(socket, nil, params) do
    %{topic: topic, reply_to: reply_to} = socket.assigns
    Polls.post(user(socket), topic, params, reply_to && reply_to.id)
  end

  defp add_poll(socket, message_id, params) do
    message = Repo.get(Messages.Message, message_id)
    message && Polls.create(user(socket), message, params)
  end

  defp poll_error(:question), do: gettext("Write the question.")
  defp poll_error(:options), do: gettext("Give at least two answers.")

  defp poll_error(:hours),
    do: gettext("Enter a number of hours above 0, at most %{max}.", max: Scheduling.max_hours())

  defp poll_error(:rate_limited),
    do: gettext("You are sending very fast. Wait a moment, then try again.")

  # `!spoiler`: on, or off again; `!spoiler:overlay text:` (steward decision, 2026-10-28)
  # on with that text over it, also for a spoiler already. The message reaches every viewer
  # as an event.
  defp toggle_spoiler(socket, message, label) do
    result =
      if is_binary(label) and String.trim(label) != "",
        do: Messages.set_spoiler(user(socket), message, true, label),
        else: Messages.set_spoiler(user(socket), message, !message.spoiler)

    case result do
      {:ok, %{spoiler: true}} ->
        put_flash(socket, :info, gettext("Your message is hidden as a spoiler."))

      {:ok, _message} ->
        put_flash(socket, :info, gettext("Your message is no longer a spoiler."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("You cannot post in this topic."))
    end
  end

  defp mine?(socket, message) do
    user = user(socket)
    user != nil and user.id == message.author_id
  end

  # One timer at a time, only while the viewer's own open message is inside its window.
  defp schedule_tick(%{assigns: %{tick: nil}} = socket) do
    %{messages: messages, unanswered_minutes: minutes} = socket.assigns

    case open_message(messages, user(socket)) do
      %{} = mine ->
        if connected?(socket) and
             DateTime.after?(
               start_new_at(mine, answered?(messages, mine), minutes),
               DateTime.utc_now()
             ),
           do: assign(socket, :tick, Process.send_after(self(), :tick, 1000)),
           else: socket

      nil ->
        socket
    end
  end

  defp schedule_tick(socket), do: socket

  # When Ctrl+Enter may start a new message (GM-05, `Idejo.Messages.may_start_new?/2`): once
  # the window has ended and, while nobody wrote below it, once it is old enough (steward
  # decision, 2026-10-23). Worked out from the messages shown, with no query (NF-01).
  defp start_new_at(mine, true, _minutes), do: mine.closes_at

  defp start_new_at(mine, false, minutes),
    do: Enum.max([mine.closes_at, DateTime.add(mine.opened_at, minutes * 60)], DateTime)

  defp answered?(messages, mine) do
    messages
    |> Enum.drop_while(&(&1.id != mine.id))
    |> Enum.drop(1)
    |> Enum.any?(&is_nil(&1.deleted_at))
  end

  # Messages keep their place; a new one goes in its own, the end but for events that came
  # out of order (GM-08: ordered by first commit).
  defp upsert(messages, message) do
    if Enum.any?(messages, &(&1.id == message.id)) do
      Enum.map(messages, &if(&1.id == message.id, do: message, else: &1))
    else
      {before, after_} = Enum.split_while(messages, &(not newer?(&1, message)))
      before ++ [message | after_]
    end
  end

  # Whether `message` comes after `ref` in the topic's order (`opened_at`, then `id`).
  defp newer?(_message, nil), do: true

  defp newer?(message, ref) do
    case DateTime.compare(message.opened_at, ref.opened_at) do
      :gt -> true
      :lt -> false
      :eq -> message.id > ref.id
    end
  end

  # A message the window may hold: one after the start of the run.
  defp within_run?(assigns, message) do
    case parts(assigns) do
      {_pinned, [first | _]} -> newer?(message, first)
      {pinned, []} -> newer?(message, pinned)
    end
  end

  # A new message, shown or not: the topic grew, its name glows in the sidebar (the Notifier
  # hook listens on the window; steward decision, 2026-10-23), and it is announced (AX-02).
  defp arrived(socket, message) do
    %{latest: latest, total: total, topic: topic, mine_last: mine_last} = socket.assigns
    viewer = user(socket)
    own? = viewer != nil and message.author_id == viewer.id and is_nil(message.deleted_at)

    socket
    |> assign(:total, total + 1)
    |> assign(:latest, if(newer?(message, latest), do: latest_of(message), else: latest))
    |> assign(:mine_last, if(own?, do: message.id, else: mine_last))
    |> track_open(viewer, message)
    |> push_event("topic_activity", %{topic_id: topic.id})
    |> announce(nil, message)
  end

  # The navigator's "My last message": deleted, the one before it takes its place. And the
  # viewer's open message (GM-09: one at most), which the composer is.
  defp track_mine(socket, message) do
    viewer = user(socket)
    socket = track_open(socket, viewer, message)

    if message.deleted_at && message.id == socket.assigns.mine_last do
      socket
      |> assign(:mine_last, TopicWindow.last_by(socket.assigns.topic, viewer))
      |> put_nav()
    else
      socket
    end
  end

  defp track_open(socket, %{id: author_id}, %{author_id: author_id, state: "open", id: id}),
    do: assign(socket, :own_open, id)

  defp track_open(%{assigns: %{own_open: id}} = socket, _viewer, %{id: id}),
    do: assign(socket, :own_open, nil)

  defp track_open(socket, _viewer, _message), do: socket

  # Before the window loads, which needs it (`load_window/5`).
  defp open_id(user, topic) when is_struct(user) do
    case Messages.open_message(user, topic) do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp open_id(_user, _topic), do: nil

  @impl true
  def handle_event(
        "commit",
        %{"body" => body} = params,
        %{assigns: %{composing_edit: id}} = socket
      )
      when is_binary(id) do
    case editing_in_composer(socket.assigns) do
      nil -> {:reply, %{error: true}, end_composer_edit(socket)}
      message -> commit_edit(socket, message, body, params["break"] == true)
    end
  end

  def handle_event("commit", %{"body" => body} = params, socket) do
    %{topic: topic, reply_to: reply_to} = socket.assigns

    opts = [
      break: params["break"] == true,
      reply_to_id: reply_to && reply_to.id,
      new: draft_over(socket.assigns) != nil
    ]

    then = params["then"]

    case Messages.commit(user(socket), topic, body, opts) do
      {:ok, nil} ->
        {:reply, %{closed: false, body: ""}, socket}

      # The message itself arrives like everyone else's, as an event.
      {:ok, message} ->
        {:reply, %{closed: message.state == "closed", body: message.body_md},
         socket
         |> put_committed(completed(socket, message, opts))
         |> after_send(then, message, params)}

      # A new message before the open one may end: the text stays, unsent.
      {:error, :too_soon} ->
        {:reply, %{error: true}, assign(socket, :too_soon?, true)}

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

  # An automessage's `!command` (steward decisions, 2026-11-01): the server posts its text,
  # as its sender; the user's own text stays in the composer.
  def handle_event("automessage", %{"name" => name}, socket) when is_binary(name) do
    case Automessages.post(user(socket), socket.assigns.topic, name) do
      {:ok, _message} ->
        {:noreply, socket}

      {:error, {:cooldown, until}} ->
        minutes = max(div(DateTime.diff(until, DateTime.utc_now()) + 59, 60), 1)

        {:noreply,
         put_flash(
           socket,
           :error,
           ngettext(
             "!%{command} was posted here lately. It can be used again in a minute.",
             "!%{command} was posted here lately. It can be used again in %{count} minutes.",
             minutes,
             command: name
           )
         )}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("You are sending very fast. Wait a moment, then try again.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("This automessage cannot be posted here."))}
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

  # `!poll` and `!spoiler` with nothing new to send: for the open message.
  # With nothing open, `!poll` posts the poll as a message of its own (steward decision,
  # 2026-10-24); `!spoiler` needs a message.
  def handle_event(command, params, socket) when command in ["open_poll", "spoiler"] do
    case open_message(socket.assigns.messages, user(socket)) do
      nil when command == "open_poll" ->
        {:noreply, open_poll(socket, nil)}

      nil ->
        {:noreply,
         put_flash(socket, :error, gettext("Write your message first, then choose !spoiler."))}

      message when command == "spoiler" ->
        {:noreply, toggle_spoiler(socket, message, params["label"])}

      message ->
        {:noreply, open_poll(socket, message)}
    end
  end

  # The poll dialog keeps what is typed, so adding an answer loses nothing.
  def handle_event("poll_change", %{"poll" => params}, %{assigns: %{poll_form: form}} = socket)
      when is_map(params) and form != nil,
      do: {:noreply, assign(socket, :poll_form, %{form | params: params})}

  def handle_event("poll_add_option", _params, %{assigns: %{poll_form: form}} = socket)
      when form != nil,
      do:
        {:noreply,
         assign(socket, :poll_form, %{form | count: min(form.count + 1, Polls.max_options())})}

  def handle_event("hide_poll", _params, socket), do: {:noreply, assign(socket, :poll_form, nil)}

  def handle_event("create_poll", %{"poll" => params}, %{assigns: %{poll_form: form}} = socket)
      when is_map(params) and form != nil do
    case add_poll(socket, form.message_id, params) do
      {:ok, _summary} ->
        {:noreply, assign(socket, :poll_form, nil)}

      {:ok, _message, _summary} ->
        {:noreply, socket |> assign(:poll_form, nil) |> assign(:reply_to, nil)}

      {:error, reason} when reason in [:question, :options, :hours, :rate_limited] ->
        {:noreply,
         assign(socket, :poll_form, %{form | params: params, error: poll_error(reason)})}

      {:error, :taken} ->
        {:noreply,
         socket
         |> assign(:poll_form, nil)
         |> put_flash(:error, gettext("This message has a poll already."))}

      _forbidden ->
        {:noreply,
         socket
         |> assign(:poll_form, nil)
         |> put_flash(:error, gettext("You cannot post in this topic."))}
    end
  end

  def handle_event("create_poll", _params, socket), do: {:noreply, socket}

  # `!spoiler`: this viewer sees the message plainly from now on.
  def handle_event("reveal_spoiler", %{"id" => id}, socket) when is_binary(id),
    do: {:noreply, assign(socket, :revealed, MapSet.put(socket.assigns.revealed, id))}

  # A `||spoiler||` in a message (steward decision, 2026-10-28), by its place among the
  # message's spoilers: this viewer sees it from now on, also as the message grows.
  def handle_event("reveal_inline_spoiler", %{"id" => id, "index" => index}, socket)
      when is_binary(id) and is_integer(index) and index >= 0,
      do: {:noreply, assign(socket, :revealed, MapSet.put(socket.assigns.revealed, {id, index}))}

  # `!poll`: a vote, or a changed one; the new counts reach every viewer as an event.
  def handle_event("vote", %{"message_id" => id} = params, socket) when is_binary(id) do
    options = for option <- List.wrap(params["options"]), is_binary(option), do: option

    with %{} = user <- user(socket),
         %Messages.Message{} = message <- Enum.find(socket.assigns.messages, &(&1.id == id)),
         {:ok, _summary} <- Polls.vote(user, message, options) do
      {:noreply, socket}
    else
      {:error, :closed} ->
        {:noreply, put_flash(socket, :error, gettext("This poll has closed."))}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, gettext("You have voted a lot lately. Please wait a little."))}

      _ ->
        {:noreply, socket}
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

  # Who reacted with what (steward decision, 2026-10-28): a right click or a long press on a
  # message's reactions; only for messages on screen, whose reactions the viewer sees.
  def handle_event("reaction_who", %{"id" => id}, socket) when is_binary(id) do
    if Map.get(socket.assigns.reactions, id, []) != [] and
         Enum.any?(socket.assigns.messages, &(&1.id == id)),
       do: {:noreply, put_reaction_who(socket, %{message_id: id, all?: false})},
       else: {:noreply, socket}
  end

  # "Show more": the same people, all of them, in a card.
  def handle_event("reaction_who_all", _params, socket) do
    case socket.assigns.reaction_who do
      %{} = who -> {:noreply, assign(socket, :reaction_who, %{who | all?: true})}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("close_reaction_who", _params, socket),
    do: {:noreply, assign(socket, :reaction_who, nil)}

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

  # TP-08: Reply without a page load. With the author's message open, the composer leaves
  # it for a new message at the end (`put_draft/1`), keeping only what was not sent yet.
  def handle_event("reply", %{"id" => id}, socket) do
    case socket.assigns.can_post? &&
           Enum.find(socket.assigns.messages, &(&1.id == id and is_nil(&1.deleted_at))) do
      %Messages.Message{} = message ->
        # The composer is at the end (steward decision, 2026-11-01): from further up, the
        # page goes there first.
        socket =
          if socket.assigns.at_end?,
            do: socket,
            else: socket |> to_end() |> push_event("scroll_to_end", %{})

        left? = socket.assigns.draft_over == nil

        socket =
          socket
          |> assign(:reply_to, message)
          |> put_draft()

        socket =
          if left? and socket.assigns.draft_over != nil and socket.assigns.composing_edit == nil,
            do: push_event(socket, "composer_sent", %{body: ""}),
            else: socket

        # AX-01: the box takes the focus, as the link's `#composer` did.
        {:noreply, push_event(socket, "composer_focus", %{})}

      _ ->
        {:noreply, socket}
    end
  end

  # Long topics (steward decision, 2026-11-01): the messages before or after the window, when
  # the reader scrolls to its edge (`phx-viewport-top` / `-bottom`, LiveView's own) or
  # presses the button between them.
  def handle_event("load_earlier", _params, %{assigns: %{earlier_count: n}} = socket)
      when n > 0,
      do: {:noreply, socket |> load_more(:earlier) |> refresh_window_data()}

  def handle_event("load_earlier", _params, socket), do: {:noreply, socket}

  def handle_event("load_later", _params, %{assigns: %{later_count: n}} = socket) when n > 0 do
    socket = socket |> load_more(:later) |> refresh_window_data()
    # At the end: what came meanwhile is read now (TP-07).
    if socket.assigns.at_end?, do: Reading.mark_read(user(socket), socket.assigns.topic)
    {:noreply, socket}
  end

  def handle_event("load_later", _params, socket), do: {:noreply, socket}

  # The navigator's links (TopicNav hook): to a message the window does not hold, the window
  # around it loads first, then the page goes to it.
  def handle_event("jump", %{"id" => id}, socket) when is_binary(id) do
    socket =
      if socket.assigns.latest && id == socket.assigns.latest.id,
        do: to_end(socket),
        else: socket |> put_window({:around, id}) |> refresh_window_data()

    {:noreply, push_event(socket, "scroll_to", %{id: "message-" <> id})}
  end

  # "N new messages", and "Jump to the end to write", whose composer then takes the focus.
  def handle_event("jump_to_end", params, socket) do
    socket = socket |> to_end() |> push_event("scroll_to_end", %{})

    if params["write"],
      do: {:noreply, push_event(socket, "composer_focus", %{})},
      else: {:noreply, socket}
  end

  # The composer stays a new message (`draft_over`), refused until it may be sent.
  def handle_event("cancel_reply", _params, socket),
    do: {:noreply, assign(socket, :reply_to, nil)}

  def handle_event("hide_too_soon", _params, socket),
    do: {:noreply, assign(socket, :too_soon?, false)}

  # Back to the open message: what was typed follows its text, unsent.
  def handle_event("append_to_open", _params, socket) do
    case draft_over(socket.assigns) do
      nil ->
        {:noreply, assign(socket, too_soon?: false)}

      open ->
        {:noreply,
         socket
         |> assign(too_soon?: false, draft_over: nil, reply_to: nil)
         |> push_event("composer_sent", %{body: open.body_md})}
    end
  end

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
    user = user(socket)
    # The composer opens in the message (steward decision, 2026-10-24): an opening message
    # pinned away from the run is loaded with the messages after it first.
    socket =
      if socket.assigns.gap and id == socket.assigns.opening_id,
        do: socket |> put_window({:around, id}) |> refresh_window_data(),
        else: socket

    case Enum.find(socket.assigns.messages, &(&1.id == id)) do
      # Steward decision, 2026-10-24: the author edits in the composer, as they wrote it.
      %{state: "closed", deleted_at: nil, author_id: author_id} = message
      when author_id == user.id ->
        {:noreply,
         socket
         |> close_editor()
         |> assign(composing_edit: id, edit_versioned?: false)
         |> push_event("composer_sent", %{body: message.body_md})
         # AX-01: the Edit button that had the focus is gone; the box takes it.
         |> push_event("composer_focus", %{})}

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
      when message.author_id == user.id and message.id != socket.assigns.opening_id ->
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
        {:noreply,
         socket
         |> assign(editing: nil, refocus: id)
         |> then(&if(&1.assigns.composing_edit == id, do: end_composer_edit(&1), else: &1))}

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

  # Editing in the composer (steward decision, 2026-10-24): the author's closed message, in
  # place, appended to like an open one. Enter saves; Ctrl+Enter saves and ends the edit, at
  # any time. One version per edit: the text from before it, kept at its first change.
  defp editing_in_composer(%{composing_edit: nil}), do: nil

  defp editing_in_composer(%{composing_edit: id, messages: messages}),
    do: Enum.find(messages, &(&1.id == id and &1.state == "closed" and is_nil(&1.deleted_at)))

  defp commit_edit(socket, message, "", _break?) do
    # Emptied: ask whether to delete it, as the editor does (not the opening message).
    if message.id != socket.assigns.opening_id,
      do: {:reply, %{error: true}, assign(socket, :confirm_delete, message.id)},
      else: {:reply, %{error: true}, socket}
  end

  defp commit_edit(socket, message, body, break?) do
    version = if socket.assigns.edit_versioned?, do: :never, else: :always

    case Messages.edit(user(socket), message, body, version: version) do
      {:ok, edited} ->
        socket =
          assign(socket, :edit_versioned?, socket.assigns.edit_versioned? or edited != message)

        if break?,
          do: {:reply, %{closed: true, body: edited.body_md}, end_composer_edit(socket)},
          else: {:reply, %{closed: false, body: edited.body_md}, socket}

      {:error, :blank} ->
        commit_edit(socket, message, "", break?)

      {:error, _} ->
        {:reply, %{error: true},
         socket
         |> end_composer_edit()
         |> put_flash(:error, gettext("This message cannot be edited."))}
    end
  end

  # The composer goes back to the author's open message, or to the end.
  defp end_composer_edit(socket) do
    id = socket.assigns.composing_edit
    socket = assign(socket, composing_edit: nil, edit_versioned?: false, refocus: id)

    case open_message(socket.assigns.messages, user(socket)) do
      %{id: open_id, body_md: body} when open_id != socket.assigns.draft_over ->
        push_event(socket, "composer_sent", %{body: body})

      _ ->
        push_event(socket, "composer_sent", %{body: ""})
    end
  end

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

  defp selectable_in_view?(assigns, message), do: message.id != assigns.opening_id

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
    # Worked out at each render, as they follow from several assigns: never kept in the
    # socket, so LiveView sees them as changed each time and the composer is always right.
    # The composer is at the end of the topic, or in a message its author edits (steward
    # decision, 2026-11-01); elsewhere the messages read as they are.
    # It is the author's open message, so that message must be loaded with it, which the end
    # always is (`jump_to_end`).
    composer? =
      assigns.can_post? and
        (assigns.composing_edit != nil or (assigns.at_end? and open_loaded?(assigns)))

    layout =
      if composer?,
        do: composer_layout(assigns),
        else: [mine: nil, locked: nil, answered?: false]

    # The opening message pinned on top, away from the window (never while the composer
    # is in it).
    opening_id = assigns.opening_id

    {pinned, window} =
      if assigns.gap and not match?(%{id: ^opening_id}, layout[:mine]),
        do: parts(assigns),
        else: {nil, assigns.messages}

    {before, after_} = split(window, layout[:mine])

    assigns =
      assigns
      |> assign(layout)
      |> assign(
        composer?: composer?,
        moderated:
          assigns.moderating && Enum.find(assigns.messages, &(&1.id == assigns.moderating)),
        opening: pinned && entries(assigns, [pinned]),
        before: entries(assigns, before),
        later: entries(assigns, after_)
      )

    ~H"""
    <%!-- Where the reader may react, the + picker loads while the page is idle
         (emoji_picker.js `preloadEmoji`). --%>
    <div
      id="topic-live"
      phx-hook="InlineLinks"
      data-topic-id={@topic && @topic.id}
      data-at-end={@at_end?}
      data-emoji-index={@can_react? && ReactionComponents.picker_index()}
      data-emoji-labels={@can_react? && ReactionComponents.picker_labels()}
    >
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
      <ReactionComponents.reaction_who :if={@reaction_who && !@reaction_who.all?} who={@reaction_who} />
      <ReactionComponents.reaction_card :if={@reaction_who && @reaction_who.all?} who={@reaction_who} />
      <.delete_own_dialog :if={@confirm_delete} />
      <.schedule_dialog :if={@schedule} schedule={@schedule} error={@schedule_error} />
      <PollComponents.poll_dialog :if={@poll_form} form={@poll_form} />
      <.too_soon_dialog :if={@too_soon?} />
      <MessageModerationComponents.moderate_card
        :if={@can_moderate? && @moderated}
        message={@moderated}
        own?={@moderated.author_id == @current_scope.user.id}
        movable?={@moderated.id != @nav.first}
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
        :if={@topic && @nav}
        title={@topic.title}
        nav={@nav}
        first_unread={@first_unread}
      />
      <p :if={@lost_access?} id="topic-gone" role="status" class="opacity-70">
        {gettext("You can no longer view this topic.")}
      </p>

      <%!-- Long topics, a window at a time (steward decision, 2026-11-01): the opening message
           pinned on top when the window starts further on, then the window, with what is not
           loaded before and after it (buttons, links without JavaScript; LiveView's
           `phx-viewport-top` / `-bottom` load more as the reader scrolls to an edge). --%>
      <div
        id="message-window"
        phx-hook="MentionGlow"
        data-mention-tags={@mention_glows != %{} && Jason.encode!(@mention_tags)}
        data-controls-mobile={@current_scope && @current_scope.user.controls_on_mobile}
        data-controls-desktop={@current_scope && @current_scope.user.controls_on_desktop}
      >
        <ol
          :if={@opening}
          id="opening-message"
          class={["message-list", @topic && "cat-#{@topic.category_id}"]}
        >
          <.message_item
            :for={{message, entry} <- @opening}
            :key={message.id}
            message={message}
            entry={entry}
            topic={@topic}
            can_post?={@can_post?}
            viewer={@current_scope && @current_scope.user}
            can_moderate?={@can_moderate?}
            can_fork?={@can_fork?}
            can_react?={@can_react?}
            live?={@live?}
          />
        </ol>
        <.window_gap
          :if={@earlier_count > 0}
          id="earlier-messages"
          label={ngettext("1 earlier message", "%{count} earlier messages", @earlier_count)}
          event="load_earlier"
          href={page_path(@topic, @page_before)}
          live?={@live?}
        />
        <ol
          id="messages"
          class={["message-list", @topic && "cat-#{@topic.category_id}"]}
          phx-viewport-top={@live? && @earlier_count > 0 && "load_earlier"}
          phx-viewport-bottom={@live? && @later_count > 0 && "load_later"}
        >
          <%!-- NF-01: an entry reads only its message, its `entry` (entry/3) and what does
               not change between updates, so an update renders and sends the entries it
               changed and no others. --%>
          <.message_item
            :for={{message, entry} <- @before}
            :key={message.id}
            message={message}
            entry={entry}
            topic={@topic}
            can_post?={@can_post?}
            viewer={@current_scope && @current_scope.user}
            can_moderate?={@can_moderate?}
            can_fork?={@can_fork?}
            can_react?={@can_react?}
            live?={@live?}
          />
          <li :if={@composer?} id={if @mine, do: "message-#{@mine.id}", else: "composer-slot"}>
            <.composer
              mine={@mine}
              pending={@pending}
              commands={IdejoWeb.ComposerCommands.for_composer(@images?, @can_fork?, @automessages)}
              punctuate?={@punctuate?}
              reply_to={@reply_to}
              locked={@locked}
              editing?={@mine != nil and @mine.id == @composing_edit}
              roles={@roles}
              author={@current_scope.user}
              now={@now}
              upload={if @images?, do: @uploads.composer_image}
              image_error={@image_error}
              poll={@mine && @polls[@mine.id]}
              answered?={@answered?}
              unanswered_minutes={@unanswered_minutes}
              private?={@topic.private}
            />
          </li>
          <.message_item
            :for={{message, entry} <- @later}
            :key={message.id}
            message={message}
            entry={entry}
            topic={@topic}
            can_post?={@can_post?}
            viewer={@current_scope && @current_scope.user}
            can_moderate?={@can_moderate?}
            can_fork?={@can_fork?}
            can_react?={@can_react?}
            live?={@live?}
          />
        </ol>
        <.window_gap
          :if={@later_count > 0}
          id="later-messages"
          label={ngettext("1 later message", "%{count} later messages", @later_count)}
          event="load_later"
          href={page_path(@topic, @page_after)}
          live?={@live?}
        />
        <%!-- New messages while the reader is further up: they go there with it. --%>
        <button
          :if={@new_below > 0}
          id="new-messages"
          type="button"
          class="new-messages btn btn-sm btn-primary"
          phx-click="jump_to_end"
        >
          <.icon name="hero-arrow-down-micro" class="size-4" />{ngettext(
            "1 new message",
            "%{count} new messages",
            @new_below
          )}
        </button>
        <%!-- The composer is at the end of the topic. --%>
        <p :if={@can_post? and !@composer?} id="jump-to-composer" class="window-gap">
          <button
            :if={@live?}
            type="button"
            class="btn btn-sm"
            phx-click="jump_to_end"
            phx-value-write="true"
          >
            {gettext("Jump to the end to write")}
          </button>
          <.link :if={!@live?} href={page_path(@topic, @last_page)} class="btn btn-sm">
            {gettext("Jump to the end to write")}
          </.link>
        </p>
      </div>

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

  attr :message, :map, required: true
  attr :entry, :map, required: true
  attr :topic, :map, required: true
  attr :can_post?, :boolean, required: true
  attr :viewer, :any, required: true
  attr :can_moderate?, :boolean, required: true
  attr :can_fork?, :boolean, required: true
  attr :can_react?, :boolean, required: true
  attr :live?, :boolean, required: true

  # A message of the list, with the "N unread messages" line above it when it is the first
  # unread one (TP-07). `:key`ed by the comprehensions that render it (NF-01).
  defp message_item(assigns) do
    ~H"""
    <li
      id={"message-#{@message.id}"}
      hidden={@entry.hidden?}
      data-mention-glow={@entry.glow}
      phx-mounted={@entry.glow && JS.ignore_attributes(["data-glowing"])}
    >
      <.unread_line :if={@entry.unread} message_id={@message.id} count={@entry.unread} />
      <.message
        message={@message}
        entry={@entry}
        topic={@topic}
        can_post?={@can_post?}
        viewer={@viewer}
        can_moderate?={@can_moderate?}
        can_fork?={@can_fork?}
        can_react?={@can_react?}
        live?={@live?}
      />
    </li>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true

  attr :event, :string,
    required: true,
    doc: "what the button pushes: `load_earlier`, `load_later`"

  attr :href, :string, required: true, doc: "the page that holds them, without JavaScript"
  attr :live?, :boolean, required: true

  # Between the window and the messages not loaded (steward decision, 2026-11-01): a button
  # that loads them (they also load when the reader scrolls to the edge), or, without
  # JavaScript, a link to the page that holds them (AX-04).
  defp window_gap(assigns) do
    ~H"""
    <p id={@id} class="window-gap">
      <button :if={@live?} type="button" class="btn btn-sm btn-ghost" phx-click={@event}>
        {@label}
      </button>
      <.link :if={!@live?} href={@href} class="btn btn-sm btn-ghost">{@label}</.link>
    </p>
    """
  end

  defp open_loaded?(%{own_open: nil}), do: true
  defp open_loaded?(%{own_open: id, messages: messages}), do: Enum.any?(messages, &(&1.id == id))

  # A page of the topic (`?page=n`, AX-04, SE-04), or of the private conversation.
  defp page_path(%{private: true, id: id}, page), do: ~p"/p/#{id}?#{[page: page]}"
  defp page_path(%{id: id, slug: slug}, page), do: ~p"/t/#{id}/#{slug}?#{[page: page]}"

  attr :title, :string, required: true
  attr :nav, :map, required: true, doc: "the messages it links to (`put_nav/1`)"
  attr :first_unread, :map, default: nil

  # The topic navigator (steward decision, 2026-10-23): once the title has scrolled away, a
  # card at the right with the title and links to the first message, the first unread, the
  # last message and the reader's own last one; where the right has no room for it (phones),
  # a small pill at the top right that opens it. Plain links to the messages' anchors
  # (TP-06); the `TopicNav` hook shows it, picks card or pill and scrolls. Without
  # JavaScript it stays hidden (the page reads the same without it, AX-04).
  defp topic_nav(assigns) do
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
            <a href={"#message-#{@nav.first}"} id="topic-nav-first">
              <.icon name="hero-chevron-double-up" class="size-4" />{gettext("First message")}
            </a>
          </li>
          <li :if={@first_unread}>
            <a href={"#message-#{@first_unread.id}"} id="topic-nav-unread">
              <.icon name="hero-sparkles" class="size-4" />{gettext("First unread")}
            </a>
          </li>
          <li>
            <a href={"#message-#{@nav.last}"} id="topic-nav-last">
              <.icon name="hero-chevron-double-down" class="size-4" />{gettext("Last message")}
            </a>
          </li>
          <li :if={@nav.mine}>
            <a href={"#message-#{@nav.mine}"} id="topic-nav-mine">
              <.icon name="hero-user" class="size-4" />{gettext("My last message")}
            </a>
          </li>
        </ul>
      </div>
    </nav>
    """
  end

  # A new message sent before the open one may end (steward decision, 2026-10-24).
  defp too_soon_dialog(assigns) do
    ~H"""
    <dialog
      id="too-soon-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="hide_too_soon"
      aria-labelledby="too-soon-title"
      aria-describedby="too-soon-text"
    >
      <div class="modal-box">
        <h2 id="too-soon-title" class="inline-card-title">{gettext("Not yet")}</h2>
        <p id="too-soon-text" class="mt-2">
          {gettext("You cannot post a new message yet. Append your old message.")}
        </p>
        <div class="modal-action">
          <button
            type="button"
            id="too-soon-append"
            class="btn btn-sm btn-primary"
            phx-click="append_to_open"
          >
            {gettext("Append to my message")}
          </button>
          <form method="dialog">
            <button class="btn btn-sm btn-ghost">{gettext("OK")}</button>
          </form>
        </div>
      </div>
    </dialog>
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

  # Each message shown, with what its entry shows besides the message itself (NF-01). The
  # list is a keyed comprehension, which renders an entry again only when its message or
  # this map changed: a change to one message (an Enter, a reaction, a vote, a spoiler
  # revealed) renders that entry alone, in every view, however long the topic.
  defp entries(assigns, messages) do
    spoilers =
      Enum.group_by(for({id, n} <- assigns.revealed, do: {id, n}), &elem(&1, 0), &elem(&1, 1))

    unread = assigns.unread_line? && assigns.first_unread
    viewer = assigns.current_scope && assigns.current_scope.user
    Enum.map(messages, &{&1, entry(assigns, &1, {spoilers, unread, viewer})})
  end

  # `refocus?`: the message whose editor just closed, which takes the focus back (AX-01).
  # `committed?`: the viewer's own message, just completed: "sent & committed" for a moment.
  # `selected`: nil outside choosing messages (TP-15, MO-02), with `selectable?` its checkbox.
  # `revealed_spoilers`: the `||spoilers||` the viewer revealed, by place. `edit`: the
  # editor, in the message being edited only. `own_closed?` and `mod_edit?`: who may edit it,
  # its author while it is closed (GM-10) or a moderator someone else's (MO-02); deleted
  # messages are edited by nobody.
  defp entry(assigns, %{id: id} = message, {spoilers, unread, viewer}) do
    run = assigns.deleted_runs[id]
    {selected, selectable?} = selection(assigns, message)
    {own_closed?, mod_edit?} = edit_rights(assigns, message, viewer)

    %{
      deleted_run: run,
      hidden?: run == :rest and !assigns.can_moderate?,
      glow: assigns.mention_glows[id],
      unread: unread_count(unread, id),
      role: Map.get(assigns.roles, message.author_id),
      reply_shown?: reply_shown?(assigns, message),
      forks: Map.get(assigns.forks, id, []),
      reactions: Map.get(assigns.reactions, id, []),
      poll: assigns.polls[id],
      selected: selected,
      selectable?: selectable?,
      revealed?: MapSet.member?(assigns.revealed, id),
      revealed_spoilers: Map.get(spoilers, id, []),
      committed?: assigns.committed == id,
      refocus?: assigns.refocus == id,
      edit: edit_state(assigns, message),
      own_closed?: own_closed?,
      mod_edit?: mod_edit?
    }
  end

  defp unread_count(%{id: id, count: count}, id), do: count
  defp unread_count(_unread, _id), do: nil

  defp selection(%{selected: nil}, _message), do: {nil, false}

  defp selection(%{selected: selected} = assigns, message),
    do: {MapSet.member?(selected, message.id), selectable_in_view?(assigns, message)}

  defp edit_rights(_assigns, _message, nil), do: {false, false}

  defp edit_rights(assigns, message, viewer) do
    editable? = message.state == "closed" and is_nil(message.deleted_at)
    own? = viewer.id == message.author_id
    {editable? and own? and assigns.can_post?, editable? and not own? and assigns.can_moderate?}
  end

  # TP-15: a quote leading to another topic shows only to readers who may view it.
  defp reply_shown?(_assigns, %{reply_to: nil}), do: false

  defp reply_shown?(assigns, %{reply_to: reply}),
    do: reply.topic_id == assigns.topic.id or MapSet.member?(assigns.viewable_replies, reply.id)

  # TP-02: the editor's state, for the message it is open in.
  defp edit_state(%{editing: {id, form}} = assigns, %{id: id}) do
    %{
      form: form,
      mode: assigns.editor_mode,
      preview_html: assigns.preview_html,
      # TP-12: allowed at mount for those who could post then; nil otherwise.
      upload: (assigns[:uploads] || %{})[:edit_image],
      image_error: assigns.image_error
    }
  end

  defp edit_state(_assigns, _message), do: nil

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

  # Where the composer goes: in the author's open message, or after Reply a new message at
  # the end, the open one reading like the others (steward decision, 2026-10-24). `locked`:
  # the open message a new message waits for, refused on Enter until it may start one.
  # `answered?`: someone wrote below the message the composer's timer runs for (GM-05).
  defp composer_layout(assigns) do
    {mine, locked} = composer_place(assigns)
    timed = locked || mine
    [mine: mine, locked: locked, answered?: timed != nil and answered?(assigns.messages, timed)]
  end

  defp composer_place(assigns) do
    mine = open_message(assigns.messages, assigns.current_scope && assigns.current_scope.user)
    editing = assigns[:composing_edit] && editing_in_composer(assigns)

    cond do
      editing -> {editing, nil}
      is_nil(mine) or mine.id != assigns[:draft_over] -> {mine, nil}
      assigns.reply_to && assigns.early_reply? -> {nil, nil}
      true -> {nil, mine}
    end
  end

  # The messages before the author's open message and the ones after it; with none open,
  # everything comes before and the composer goes to the end.
  defp split(messages, nil), do: {messages, []}

  defp split(messages, mine) do
    case Enum.split_while(messages, &(&1.id != mine.id)) do
      {before, [_mine | after_]} -> {before, after_}
      {before, []} -> {before, []}
    end
  end

  attr :author, :map, required: true
  attr :role, :any, required: true, doc: "the author's role shown next to the name, or nil"
  attr :role?, :boolean, default: true, doc: "false: the role waits (the composer's status)"
  slot :status, doc: "a bubble at the right of the name, in place of the role"

  defp author_line(assigns) do
    ~H"""
    <span class="author-line">
      <UserComponents.avatar user={@author} size={:list} />
      <%!-- TP-10: the name, and the user tag with it, open the user's card, like an @mention
           (InlineLinks hook). --%>
      <a href={~p"/u/#{@author.id}"} class="author-name font-semibold">
        {@author.display_name}<UserComponents.user_tag user={@author} />
      </a>
      {render_slot(@status)}
      <Admin.role_label :if={@role && @role?} role={@role} class="author-role" />
    </span>
    """
  end

  attr :message, :map, required: true

  attr :entry, :map,
    required: true,
    doc: "what the entry shows besides the message: its reactions, poll, editor… (`entry/3`)"

  attr :topic, :map, required: true
  attr :can_post?, :boolean, required: true
  attr :viewer, :any, required: true
  attr :can_moderate?, :boolean, required: true
  attr :can_fork?, :boolean, required: true
  attr :can_react?, :boolean, default: false
  attr :live?, :boolean, default: false

  # Open and closed messages look the same to readers (GM-07). Nothing is worked out here:
  # everything comes in through attributes, so a change to one of `@entry`'s fields renders
  # only what shows it (NF-01).
  defp message(assigns) do
    ~H"""
    <%!-- MO-02: readers see a placeholder for a deleted message, one line for a run of them. --%>
    <p
      :if={@message.deleted_at && !@can_moderate? && match?({:first, _, _}, @entry.deleted_run)}
      id={"message-#{@message.id}-deleted"}
      class="message-deleted"
      tabindex="-1"
      phx-mounted={@entry.refocus? && JS.focus()}
    >
      {deleted_text(@entry.deleted_run)}
    </p>
    <article
      :if={is_nil(@message.deleted_at) or @can_moderate?}
      aria-labelledby={"message-#{@message.id}-author"}
      class="message"
      phx-mounted={JS.ignore_attributes(["data-acting"])}
    >
      <p id={"message-#{@message.id}-author"} class="message-head">
        <%!-- Choosing messages to move (TP-15) or delete (MO-02). --%>
        <label :if={@entry.selected != nil and @entry.selectable?} class="move-select">
          <input
            type="checkbox"
            id={"select-#{@message.id}"}
            checked={@entry.selected}
            phx-click="toggle_select"
            phx-value-id={@message.id}
          />
          <span class="sr-only">
            {gettext("Select the message by %{name}", name: @message.author.display_name)}
          </span>
        </label>
        <.author_line author={@message.author} role={@entry.role} role?={!@entry.committed?}>
          <:status :if={@entry.committed?}>
            <span class="tutorial-bubble is-always composer-status" data-status="committed">
              {gettext("sent & committed")}
            </span>
          </:status>
        </.author_line>
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
        <%= if @entry.reply_shown? do %>
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
        :if={@entry.edit}
        for={@entry.edit.form}
        id={"edit-message-#{@message.id}"}
        phx-change="validate_edit"
        phx-submit="save_edit"
        phx-mounted={JS.focus(to: "#edit-message-#{@message.id} textarea")}
      >
        <MessageComponents.editor
          field={@entry.edit.form[:body]}
          label={
            if @entry.mod_edit?,
              do: gettext("Edit this message (Markdown)"),
              else: gettext("Edit your message (Markdown)")
          }
          mode={@entry.edit.mode}
          preview_html={@entry.edit.preview_html}
          upload={@entry.edit.upload}
          image_error={@entry.edit.image_error}
        />
        <.input
          :if={@entry.mod_edit?}
          field={@entry.edit.form[:reason]}
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
      <%!-- `!spoiler` (steward decision, 2026-10-23): blurred under a Reveal button until the
           reader reveals it; out of reach of the keyboard and screen readers until then. The
           stylesheet shows the cover only when scripts run, as the button needs them. --%>
      <div
        id={"message-#{@message.id}-content"}
        class={["message-content", @message.spoiler && !@entry.revealed? && "is-spoiler"]}
      >
        <div
          id={"message-#{@message.id}-hidden"}
          tabindex="-1"
          inert={@message.spoiler and !@entry.revealed? and @live?}
        >
          <%!-- A poll posted on its own: its question says it all. --%>
          <MessageComponents.collapsible_body
            :if={!@entry.edit and !Polls.poll_only?(@message, @entry.poll)}
            id={"message-#{@message.id}-body"}
            html={
              if @live?,
                do: MessageComponents.inline_spoilers(@message.body_html, @entry.revealed_spoilers),
                else: @message.body_html
            }
          />
          <%!-- It reads the clock when it is drawn: a vote, or its closing time
               (`Idejo.Messages.PollWorker`), sends `{:poll, …}`, which draws it again. --%>
          <PollComponents.poll
            :if={@entry.poll && (is_nil(@message.deleted_at) or @can_moderate?)}
            poll={@entry.poll}
            message={@message}
            viewer={@viewer}
            can_vote?={@can_post? and is_nil(@message.deleted_at)}
            now={DateTime.utc_now()}
          />
        </div>
        <div :if={@message.spoiler and !@entry.revealed?} class="spoiler-cover">
          <%!-- `!spoiler:overlay text:` (steward decision, 2026-10-28). --%>
          <p
            :if={@message.spoiler_label}
            id={"message-#{@message.id}-spoiler-label"}
            class="spoiler-label"
          >
            {@message.spoiler_label}
          </p>
          <button
            type="button"
            id={"message-#{@message.id}-reveal"}
            class="spoiler-reveal"
            phx-click={
              JS.remove_attribute("inert", to: "#message-#{@message.id}-hidden")
              |> JS.push("reveal_spoiler", value: %{id: @message.id})
              |> JS.focus(to: "#message-#{@message.id}-hidden")
            }
          >
            <.icon name="hero-eye-micro" class="size-4" />{gettext("Reveal spoiler")}
          </button>
        </div>
      </div>
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
        summary={@entry.reactions}
        viewer={@viewer}
        can_react?={@can_react? and is_nil(@message.deleted_at)}
      />
      <%!-- TP-09: a "Continue topic" button to each topic started from this message (steward
           decision, 2026-10-23); its title is in the name, and on hover. --%>
      <p :if={@entry.forks != []} id={"message-#{@message.id}-forks"} class="message-forks">
        <.link
          :for={fork <- @entry.forks}
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
          :if={(@entry.own_closed? or @entry.mod_edit?) and !@entry.edit}
          id={"message-#{@message.id}-edit"}
          type="button"
          class="message-action"
          phx-mounted={@entry.refocus? && JS.focus()}
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
        <%!-- TP-08: connected, Reply shows the quote over the composer at once; without
             JavaScript it is a link that loads the page with it. --%>
        <button
          :if={@live? and @can_post? and is_nil(@message.deleted_at)}
          type="button"
          id={"message-#{@message.id}-reply"}
          class="message-action"
          phx-click="reply"
          phx-value-id={@message.id}
          aria-label={gettext("Reply to %{name}", name: @message.author.display_name)}
        >
          <.icon name="hero-arrow-uturn-left-micro" class="size-4" />{gettext("Reply")}
        </button>
        <.link
          :if={!@live? and @can_post? and is_nil(@message.deleted_at)}
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

  attr :punctuate?, :boolean,
    default: true,
    doc: "the author's \"Automatic punctuation\", for the Composer hook's dot rule"

  attr :reply_to, :any, required: true

  attr :locked, :any,
    default: nil,
    doc: "the open message a new message waits for, after Reply (steward decision, 2026-10-24)"

  attr :editing?, :boolean,
    default: false,
    doc: "`mine` is a closed message the author edits (steward decision, 2026-10-24)"

  attr :roles, :map, required: true
  attr :author, :map, required: true
  attr :now, DateTime, required: true
  attr :upload, :any, required: true
  attr :image_error, :string, required: true
  attr :poll, :map, default: nil, doc: "the open message's poll (`!poll`)"
  attr :answered?, :boolean, default: true, doc: "someone wrote below the open message"
  attr :unanswered_minutes, :integer, default: 10
  attr :private?, :boolean, default: false, doc: "a private conversation: no slow mode"

  # No countdown, button or status around it (GM-07): only the text box. The hook owns its
  # contents (phx-update="ignore"); `data-sent` gives it the open message after a reload.
  # The open state and the time left are hidden text describing the box (AX-03).
  defp composer(assigns) do
    %{now: now} = assigns
    # The timer runs for the open message, or for the one a new message waits for; an edit
    # has none (Ctrl+Enter ends it at any time).
    mine = if assigns.editing?, do: nil, else: assigns.mine || assigns.locked
    # No slow mode in a private conversation (steward decision, 2026-10-27): no timer line.
    answered? = assigns.answered? or assigns.private?

    assigns =
      assign(assigns,
        timed: mine,
        left: mine && DateTime.diff(mine.closes_at, now),
        # GM-05: alone below the last message, Ctrl+Enter waits for an answer or the time.
        lone_left:
          mine && !answered? &&
            DateTime.diff(start_new_at(mine, false, assigns.unanswered_minutes), now),
        # The line under the composer (steward decision, 2026-10-23) runs to this moment.
        ready_at:
          mine && !assigns.private? &&
            start_new_at(mine, answered?, assigns.unanswered_minutes)
      )

    ~H"""
    <section aria-label={gettext("Your message")} class="message message-mine">
      <%!-- Appends to messages above while the author types (steward decision, 2026-10-25):
           the Composer hook fills it; decorative, like the burn it counts. --%>
      <div
        id="composer-appended"
        class="composer-appended"
        phx-update="ignore"
        aria-hidden="true"
        data-label-one={gettext("1 message above has been appended")}
        data-label-other={gettext("%{count} messages above have been appended", count: "%{count}")}
      >
      </div>
      <%!-- Before the first Enter too, so the box never moves down when the message opens
           (steward report, 2026-10-31), faded until something is sent, with the message's
           status at the right of the name in place of the role (steward decision,
           2026-10-31; the Composer hook keeps it current), hidden until the author types
           (steward decision, 2026-10-31). An edit shows the role. --%>
      <p class="message-head composer-head">
        <.author_line author={@author} role={@roles[@author.id]} role?={@editing?}>
          <:status :if={!@editing?}>
            <span
              id="composer-status"
              class="tutorial-bubble is-always composer-status"
              phx-update="ignore"
              data-status={if @mine, do: "sent", else: "empty"}
              data-label-unsent={gettext("unsent")}
              data-label-sent={gettext("sent")}
              data-label-appends={gettext("sent, appends unsent")}
            >
              {if @mine, do: gettext("sent")}
            </span>
          </:status>
        </.author_line>
      </p>
      <div :if={@reply_to && !@editing?} id="replying-to" class="message-quote">
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
        data-editing={@editing?}
        data-commands={Jason.encode!(@commands)}
        data-punctuate={to_string(@punctuate?)}
        data-label-send={gettext("Enter to send")}
        data-label-sent={gettext("Sent!")}
        data-label-continue={gettext("Continue typing to add to your message")}
        data-label-visible={
          if @private?,
            do: gettext("Message delivered!"),
            else: gettext("Message now visible to all!")
        }
        data-label-image={gettext("image:")}
      >
        <div class="composer-backdrop" aria-hidden="true"></div>
        <textarea
          class="composer-input"
          rows="1"
          autocomplete="off"
          aria-label={gettext("Message")}
          aria-describedby="composer-window"
          placeholder={
            gettext("Enter: send · Shift+Enter: new line · Ctrl+Enter / Enter×3: New message")
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
      <%!-- Until Ctrl+Enter may start a new message (steward decision, 2026-10-23): a thin
           line filling up under the box, to the window's end, or while nobody wrote below, to
           the unanswered message time's. The `ComposerTimer` hook draws it; decorative, as
           #composer-window says the same in words (AX-03). Its slot keeps the line's room
           from the start, before a message opens and after it closes, so the page never grows
           or shrinks with it (steward report, 2026-10-31); a private conversation has none. --%>
      <div :if={!@private?} class="composer-timer-slot">
        <div
          :if={@ready_at}
          id="composer-timer"
          class="composer-timer"
          phx-hook="ComposerTimer"
          data-start={DateTime.to_unix(@timed.opened_at, :millisecond)}
          data-end={DateTime.to_unix(@ready_at, :millisecond)}
          data-now={DateTime.to_unix(@now, :millisecond)}
          aria-hidden="true"
          hidden
          phx-mounted={JS.ignore_attributes(["hidden"])}
        >
          <span id="composer-timer-line" class="composer-timer-line" phx-update="ignore"></span>
          <%!-- In front of the line while it fills, then in the middle (steward decision,
             2026-10-25). --%>
          <span
            id="composer-timer-bubble"
            class="tutorial-bubble composer-timer-bubble"
            phx-update="ignore"
            data-label-done={gettext("Ctrl+Enter to start new message")}
          >
            {gettext("slow mode")}
          </span>
          <%!-- At the bubble's right while it says "slow mode", three lines in turn (steward
             decision, 2026-10-25). --%>
          <span
            id="composer-timer-hint"
            class="composer-hint composer-timer-hint"
            phx-update="ignore"
            data-labels={
              Jason.encode!([
                gettext("You cannot start a new message..."),
                gettext("...but you can continue the one above."),
                gettext("[Enter] to send always works.")
              ])
            }
          ></span>
        </div>
      </div>
      <p id="composer-window" class="sr-only">
        <%= cond do %>
          <% @editing? -> %>
            {gettext(
              "You are editing your message. Enter saves it; Ctrl+Enter, or Enter three times, saves it and ends the edit."
            )}
          <% @locked && @ready_at && DateTime.compare(@ready_at, @now) == :gt -> %>
            {gettext(
              "This is a new message. Enter sends it once your open message's timer has ended."
            )}
          <% is_nil(@timed) or @locked -> %>
            {gettext("Enter starts a new message.")}
          <% @lone_left && @lone_left > 0 -> %>
            {gettext("Your message is open.")}
            {ngettext(
              "Ctrl+Enter, or Enter three times, starts a new message once someone writes below it, or in %{count} minute.",
              "Ctrl+Enter, or Enter three times, starts a new message once someone writes below it, or in %{count} minutes.",
              div(@lone_left + 59, 60)
            )}
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
      <%!-- `!poll`: under the author's message, as readers see it. --%>
      <PollComponents.poll
        :if={@poll}
        poll={@poll}
        message={@mine}
        viewer={@author}
        can_vote?={true}
        now={@now}
      />
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
