# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages do
  @moduledoc """
  The growing-message engine (GM, CLAUDE.md "Growing-message invariants").

  The composer sends the author's whole message as it reads after each Enter: `commit/4`
  stores it, in the database first (NF-02), and only then acknowledges and broadcasts it.

    * With no open message in the topic, Enter opens one (GM-01). Its window is fixed now:
      `closes_at = timer_from + window` (GM-03), `timer_from` when the author started typing
      (`typing/2`, steward request 2026-11-09; else the first commit), never after
      `opened_at`.
    * With one open, Enter commits to it in place (GM-02), whatever the time: the window only
      limits when a new message may start (GM-03, GM-04).
    * Ctrl+Enter (`break: true`) commits too; after the window it then closes the message, so
      the next line starts a new one (GM-05).

  Text that does not end with punctuation gets a `.` (GM-02; the composer shows the space
  after it) while the author's "Automatic punctuation" (`users.auto_punctuation`) is on. A commit that changes text already sent keeps the previous full text as a
  version (GM-11); appends keep none. An author has at most one open message per topic
  (GM-09, also a unique index), and a topic's first message is never open (GM-14).

  Events go to `"topic:{id}"` on `Idejo.PubSub`: `{:message, message}` after each commit or
  close, and `{:window_ended, message_id}` from `Idejo.Messages.OpenMessage`.
  """

  import Ecto.Query, warn: false
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Accounts.User
  alias Idejo.Api.ClientState
  alias Idejo.Federation
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages.{Authors, Body, Message, OpenMessage, Version}
  alias Idejo.Moderation
  alias Idejo.Notifications
  alias Idejo.RateLimit
  alias Idejo.Repo
  alias Idejo.Settings

  @shown [:author, :versions, reply_to: :author, forwarded_from: [:author, :topic]]
  @pubsub Idejo.PubSub

  @doc "Subscribes the caller to a topic's message events."
  @spec subscribe(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe(topic_id), do: Phoenix.PubSub.subscribe(@pubsub, "topic:" <> topic_id)

  @doc "Unsubscribes the caller from a topic's message events."
  @spec unsubscribe(Ecto.UUID.t()) :: :ok
  def unsubscribe(topic_id), do: Phoenix.PubSub.unsubscribe(@pubsub, "topic:" <> topic_id)

  @doc """
  Broadcasts a message event on a topic. A `{:message, message}` goes out with what a topic
  view shows of it loaded (author, versions, the message it replies to), loaded here once
  rather than by each of the topic's viewers (NF-01), with the role shown next to the
  author's name (`author_role`). Call it once the message's transaction
  has committed: it also announces the notifications written with it
  (`Idejo.Notifications.announce/1`).
  """
  @spec broadcast(Ecto.UUID.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic_id, {:message, %Message{} = message}) do
    [message] =
      message |> Repo.preload(shown(), force: true) |> List.wrap() |> with_version_html()

    # The role next to the author's name, once here rather than by each viewer new to the
    # author: 200 viewers of a topic where 30 people start writing asked for it 6,000 times.
    message = %{
      message
      | author_role: Idejo.Access.shown_role(Idejo.Access.roles_of(message.author))
    }

    # Committed: the notifications written with it go out live too.
    :ok = Notifications.announce(message)
    Phoenix.PubSub.broadcast(@pubsub, "topic:" <> topic_id, {:message, message})
  end

  def broadcast(topic_id, event),
    do: Phoenix.PubSub.broadcast(@pubsub, "topic:" <> topic_id, event)

  @doc """
  The messages with their earlier versions' HTML (GM-11), rendered once here: a topic view
  shows them under "view earlier version", and rendered by each viewer each edited message
  cost every viewer a Markdown rendering per version at every update of it. Versions not
  loaded are left alone.
  """
  @spec with_version_html([Message.t()]) :: [Message.t()]
  def with_version_html(messages) do
    Enum.map(messages, fn
      %Message{versions: [_ | _] = versions} = message ->
        context = Body.context(message)
        %{message | versions: Enum.map(versions, &version_html(&1, context))}

      message ->
        message
    end)
  end

  defp version_html(%{body_html: nil} = version, context),
    do: %{version | body_html: Body.to_html(version.body_md, context)}

  defp version_html(version, _context), do: version

  @doc "What a topic view shows of a message besides its own fields, for `Repo.preload/2`."
  @spec shown() :: list()
  def shown do
    # Plugins (steward request, 2026-11-08): what they added, only while one is on (a query
    # less on every page of a server without any).
    if Idejo.Plugins.active() == %{}, do: @shown, else: [:embeds | @shown]
  end

  @doc """
  The message with what a topic view shows of it loaded (`shown/0`). A message from
  `broadcast/2` has it all loaded already, so this costs no query then (NF-01).
  """
  @spec with_shown(Message.t()) :: Message.t()
  def with_shown(%Message{} = message), do: Repo.preload(message, shown())

  @doc "Returns the author's open message in the topic, or `nil` (GM-09: at most one)."
  @spec open_message(User.t(), Topic.t()) :: Message.t() | nil
  def open_message(%User{id: author_id}, %Topic{id: topic_id}) do
    Repo.one(
      from m in Message,
        where: m.topic_id == ^topic_id and m.author_id == ^author_id and m.state == "open"
    )
  end

  @doc """
  Commits `text`, the author's whole message as the composer shows it, with Enter, or with
  Ctrl+Enter when `break: true`. See the module doc for the rules.

  Returns `{:ok, message}` once the commit is stored: the message as it now is, open or (after
  Ctrl+Enter past the window) closed; `{:ok, nil}` for an empty Enter with nothing open.
  `{:error, :forbidden}` without the post right or in a locked or archived topic
  (`Idejo.Forum.can_post?/2`).

  ## Options

    * `:break` - Ctrl+Enter. Defaults to `false`.
    * `:reply_to_id` - when this Enter opens a message, the message it replies to (TP-08).
    * `:forwarded_from_id` - when this Enter opens a message, the message it forwards (steward
      decision, 2026-11-02): any message the author may read, from any topic, not deleted;
      like a reply, it may start a new message early.
    * `:allow_empty` - with nothing open, an empty `text` opens an empty message instead of
      changing nothing (a plugin's block added before anything is written, steward request
      2026-11-09); with a message open, it is returned unchanged.
    * `:started_at` - for callers on the server only (tests, imports), never a client's
      value: when the author started typing the message this Enter opens. Without it, the
      time `typing/2` kept in the calling process, else now.
    * `:new` - `text` is a new message, written after "Reply" (steward decision,
      2026-10-24), not the open one: the open message closes first. Allowed when Ctrl+Enter
      would start a new message (`may_start_new?/2`) or, for a reply, at any time while the
      `gm_early_reply` setting is on; else `{:error, :too_soon}`, and nothing changes.
  """
  @spec commit(User.t(), Topic.t(), String.t(), keyword()) ::
          {:ok, Message.t() | nil}
          | {:error, :forbidden | :rate_limited | :too_soon | Ecto.Changeset.t()}
  def commit(%User{} = author, %Topic{} = topic, text, opts \\ []) when is_binary(text) do
    result =
      Repo.transact(fn ->
        # Locked, so the open message and the topic's state cannot change under this commit.
        topic = Repo.one!(from t in Topic, where: t.id == ^topic.id, lock: "FOR UPDATE")

        cond do
          not Forum.can_post?(author, topic) -> {:error, :forbidden}
          # SP-05: every Enter counts.
          RateLimit.check(:commit, author.id) != :ok -> {:error, :rate_limited}
          true -> commit_locked(author, topic, normalize(text, author.auto_punctuation), opts)
        end
      end)

    case result do
      {:ok, {:opened, message}} ->
        typing_done(author, topic)
        after_commit(message)
        opened(topic)
        {:ok, message}

      # The open message closed for the new one: announced first, so viewers see it end.
      {:ok, {closed, message}} ->
        typing_done(author, topic)
        after_commit(closed)
        after_commit(message)
        opened(topic)
        {:ok, message}

      {:ok, %Message{} = message} ->
        typing_done(author, topic)
        after_commit(message)
        result

      result ->
        result
    end
  end

  # AP-15: a new message is activity in the topic's category (the app's category channel).
  defp opened(%Topic{category_id: category_id, id: id}),
    do: Forum.broadcast_category(category_id, {:topic_activity, id})

  defp commit_locked(author, topic, text, opts) do
    open = open_message(author, topic)

    case empty_commit(open, text, opts[:allow_empty] == true) do
      {:done, result} -> result
      :commit -> commit_text(author, topic, open, text, DateTime.utc_now(), opts)
    end
  end

  # An empty Enter with nothing open changes nothing, unless a plugin's block starts the
  # message (`allow_empty:`); then, with a message already being written, it is left as is.
  defp empty_commit(nil, "", false), do: {:done, {:ok, nil}}
  defp empty_commit(%Message{} = open, "", true), do: {:done, {:ok, open}}
  defp empty_commit(_open, _text, _allow_empty?), do: :commit

  defp commit_text(author, topic, open, text, now, opts) do
    cond do
      open != nil and opts[:new] == true ->
        start_over(author, topic, open, text, now, quotes(author, topic, opts))

      # SP-05: and a new message counts towards the new messages a minute. A message closed
      # early by Ctrl+Enter holds the next back until its timers run out.
      open == nil ->
        opts = quotes(author, topic, opts)

        with :ok <- not_held(author, topic, now, opts),
             :ok <- RateLimit.check(:new_message, author.id),
             {:ok, message} <- open_new(author, topic, text, now, opts),
             do: {:ok, {:opened, message}}

      true ->
        append(open, text, now, Keyword.get(opts, :break, false))
    end
  end

  # A new message while one is open (`:new`): the open one closes first (GM-09: one open).
  defp start_over(_author, _topic, _open, "", _now, _opts), do: {:ok, nil}

  defp start_over(author, topic, open, text, now, opts) do
    with :ok <-
           if(early_reply?(opts) or may_start_new?(open, now), do: :ok, else: {:error, :too_soon}),
         :ok <- RateLimit.check(:new_message, author.id),
         {:ok, closed} <- close_locked(open, now),
         {:ok, message} <- open_new(author, topic, text, now, opts) do
      {:ok, {closed, message}}
    end
  end

  # What a new message quotes, as the author may: the message it replies to, of this topic and
  # not deleted (TP-08), and the one it forwards (`forwarded_from/2`). Ids that lead nowhere
  # are dropped, so they neither quote nor let the message start early (`early_reply?/1`).
  defp quotes(author, topic, opts) do
    opts
    |> Keyword.put(:reply_to_id, reply_to(topic, opts[:reply_to_id]))
    |> Keyword.put(:forwarded_from_id, forwarded_from(author, opts[:forwarded_from_id]))
  end

  # Reply or Forward starts a new message at any time while `gm_early_reply` is on (steward
  # decision, 2026-10-24). The ids are those `quotes/3` kept.
  defp early_reply?(opts) do
    quoting? = Enum.any?([opts[:reply_to_id], opts[:forwarded_from_id]], &(&1 not in [nil, ""]))
    quoting? and early_reply_allowed?()
  end

  @doc """
  Whether a Reply or a Forward may start a new message while the timers still run: the
  `gm_early_reply` setting, "Allow replies even if the timer is still running" (steward
  decision, 2026-10-24).
  """
  @spec early_reply_allowed?() :: boolean()
  def early_reply_allowed?, do: Settings.get(:gm_early_reply)

  defp not_held(author, topic, now, opts) do
    case held_until(author, topic, now) do
      nil -> :ok
      _until -> if early_reply?(opts), do: :ok, else: {:error, :too_soon}
    end
  end

  @doc """
  When `author` may start a new message in `topic` after closing their last one early with
  Ctrl+Enter (steward request, 2026-11-09): the moment its timers run out (the window, and
  while nobody wrote below it the unanswered message time), or nil when nothing holds them.
  """
  @spec held_until(User.t(), Topic.t(), DateTime.t()) :: DateTime.t() | nil
  def held_until(%User{id: author_id}, %Topic{id: topic_id}, now \\ DateTime.utc_now()) do
    last =
      Repo.one(
        from m in Message,
          where: m.topic_id == ^topic_id and m.author_id == ^author_id,
          order_by: [desc: m.opened_at, desc: m.id],
          limit: 1
      )

    with %Message{held: true, deleted_at: nil} = held <- last,
         false <- may_start_new?(held, now) do
      start_new_time(held)
    else
      _ -> nil
    end
  end

  # When Ctrl+Enter would have started a new message: the window's end, and while nobody
  # wrote below, the unanswered message time's.
  defp start_new_time(message),
    do: start_new_at(message, answered?(message), unanswered_seconds())

  @doc """
  When Ctrl+Enter may complete `message` and start a new one (GM-05): the window's end
  (`closes_at`), and while nobody wrote below it (`answered?` false), also the end of the
  unanswered message time, `unanswered_seconds` after its timers started (`timer_start/1`).
  The one formula: `may_start_new?/2` and `held_until/3` use it, and so does a topic view
  with what it shows (no query, NF-01). A private conversation counts as answered: it has no
  unanswered message time.
  """
  @spec start_new_at(Message.t(), boolean(), non_neg_integer()) :: DateTime.t()
  def start_new_at(%Message{closes_at: closes_at}, true = _answered?, _unanswered_seconds),
    do: closes_at

  def start_new_at(%Message{} = message, false, unanswered_seconds),
    do:
      Enum.max(
        [message.closes_at, DateTime.add(timer_start(message), unanswered_seconds, :second)],
        DateTime
      )

  @doc """
  Whether someone wrote below `message` among `messages`, in topic order: a message after it
  that is not deleted. `messages` are what a view holds; the database's answer is the same
  for every message loaded after it.
  """
  @spec answered_among?([Message.t()], Message.t()) :: boolean()
  def answered_among?(messages, %Message{id: id}) do
    messages
    |> Enum.drop_while(&(&1.id != id))
    |> Enum.drop(1)
    |> Enum.any?(&is_nil(&1.deleted_at))
  end

  @doc """
  The window a new message opens with in `topic`, in seconds (GM-15): the
  `gm_window_seconds` setting, or none in a private conversation (steward decision,
  2026-10-27: no slow mode there).
  """
  @spec window_seconds(Topic.t()) :: non_neg_integer()
  def window_seconds(%Topic{private: true}), do: 0
  def window_seconds(%Topic{}), do: Settings.get(:gm_window_seconds)

  @doc """
  Notes that the author, in the calling process (a topic view), started typing a new message
  in `topic` (`true`), or emptied it before sending (`false`); steward request, 2026-11-09.
  The time is the server's, kept in the caller's process: the next message opened in that
  topic from this process starts its timers then (`commit/4`), so a client can never set it
  back. Returns the time kept, the first keystroke's (typing again changes nothing), or nil.
  """
  @spec typing(Topic.t(), boolean()) :: DateTime.t() | nil
  def typing(%Topic{id: topic_id}, true) do
    case Process.get({__MODULE__, :typing, topic_id}) do
      %DateTime{} = at ->
        at

      nil ->
        at = DateTime.utc_now()
        Process.put({__MODULE__, :typing, topic_id}, at)
        at
    end
  end

  def typing(%Topic{id: topic_id}, false) do
    Process.delete({__MODULE__, :typing, topic_id})
    nil
  end

  @doc """
  `typing/2` for a client whose requests each run in their own process (the app, AP-14;
  steward decision, 2026-11-10): the first keystroke's time is kept for `author` and `topic`
  in `Idejo.Api.ClientState`, on the server's clock, and `commit/4` reads it when a message
  opens. Refused like a commit for someone who may not post there (`{:error, :forbidden}`),
  and rate-limited as an Enter (`:commit`). Returns the time kept, or nil after `false`.
  """
  @spec typing(User.t(), Topic.t(), boolean()) ::
          {:ok, DateTime.t() | nil} | {:error, :forbidden | :rate_limited}
  def typing(%User{} = author, %Topic{} = topic, typing?) when is_boolean(typing?) do
    cond do
      not Forum.can_post?(author, topic) ->
        {:error, :forbidden}

      RateLimit.check(:commit, author.id) != :ok ->
        {:error, :rate_limited}

      typing? ->
        {:ok, ClientState.put_new({:typing, author.id, topic.id}, DateTime.utc_now())}

      true ->
        :ok = ClientState.delete({:typing, author.id, topic.id})
        {:ok, nil}
    end
  end

  # The first keystroke: this process's (a topic view), else a client's (the app).
  defp typing_started(%User{id: author_id}, %Topic{id: topic_id}),
    do:
      Process.get({__MODULE__, :typing, topic_id}) ||
        ClientState.get({:typing, author_id, topic_id})

  defp typing_done(%User{id: author_id}, %Topic{id: topic_id}) do
    Process.delete({__MODULE__, :typing, topic_id})
    ClientState.delete({:typing, author_id, topic_id})
  end

  @doc """
  What the composer of `author` in `topic` shows (AP-14), from the one formula
  (`start_new_at/3`), so a client never works the rules out itself:

    * `open_message_id`: their open message, or nil;
    * `may_start_new_at`: when Ctrl+Enter may complete it and start a new one (nil with
      nothing open);
    * `held_until`: when the next message may start after one closed early (`held_until/3`);
    * `typing_since`: the first keystroke kept for the next message, or nil;
    * `window_seconds`, `unanswered_seconds` (none in a private conversation) and
      `reply_allowed_early` (`gm_early_reply`).
  """
  @spec composer(User.t(), Topic.t(), DateTime.t()) :: map()
  def composer(%User{} = author, %Topic{} = topic, now \\ DateTime.utc_now()) do
    open = open_message(author, topic)

    %{
      open_message_id: open && open.id,
      may_start_new_at: open && start_new_time(open, topic),
      held_until: held_until(author, topic, now),
      typing_since: typing_started(author, topic),
      window_seconds: window_seconds(topic),
      unanswered_seconds: if(topic.private, do: 0, else: unanswered_seconds()),
      reply_allowed_early: early_reply_allowed?(),
      may_post: Forum.can_post?(author, topic)
    }
  end

  defp start_new_time(message, %Topic{private: true}), do: start_new_at(message, true, 0)
  defp start_new_time(message, _topic), do: start_new_time(message)

  @doc """
  `commit/4` from a client whose requests are not a live view of the topic (the app,
  AP-14). Same rules and answers. While the author has no live view of the topic (neither
  a page nor the app's topic channel, `Idejo.Messages.Authors`), the disconnect grace
  starts (GM-12), as when a topic page closes: their open message closes once they have
  been away for it, unless they come back.
  """
  @spec commit_from_client(User.t(), Topic.t(), String.t(), keyword()) ::
          {:ok, Message.t() | nil}
          | {:error, :forbidden | :rate_limited | :too_soon | Ecto.Changeset.t()}
  def commit_from_client(%User{} = author, %Topic{} = topic, text, opts \\ [])
      when is_binary(text) do
    result = commit(author, topic, text, opts)

    with {:ok, %Message{state: "open"}} <- result,
         false <- Authors.present?(topic.id, author.id) do
      Authors.absent(topic.id, author.id)
    end

    result
  end

  @doc """
  An edit of the author's closed message from a client (the app, AP-14): `edit/4` with one
  version per edit (GM-11, TP-05), as the web composer's Edit keeps: the text from before
  the edit is kept at its first change; later Enters of the same edit keep none. `finish:
  true` (Ctrl+Enter) saves and ends the edit, so the next one keeps a version again. The
  edit in progress is kept in `Idejo.Api.ClientState` for an hour.
  """
  @spec edit_from_client(User.t(), Message.t(), String.t(), boolean()) ::
          {:ok, Message.t()} | {:error, :forbidden | :blank | Ecto.Changeset.t()}
  def edit_from_client(%User{} = author, %Message{} = message, text, finish?)
      when is_binary(text) do
    key = {:edit, author.id, message.id}
    version = if ClientState.get(key), do: :never, else: :always

    result = edit(author, message, text, version: version)

    case result do
      {:ok, edited} ->
        cond do
          finish? -> ClientState.delete(key)
          edited.body_md != message.body_md -> ClientState.put_new(key, true)
          true -> :ok
        end

      _error ->
        :ok
    end

    result
  end

  # The text as sent: line ends trimmed, and a `.` after text that ends without punctuation,
  # unless the author turned automatic punctuation off (steward decision, 2026-10-26).
  defp normalize(text, punctuate?) do
    text = String.trim_trailing(text)
    if text == "" or not punctuate? or ends_in_punctuation?(text), do: text, else: text <> "."
  end

  # Code ends without punctuation too, and a dot there would become part of the code: after a
  # fence, inside a fence still open, or on an indented code line, nothing is added.
  defp ends_in_punctuation?(text) do
    lines = String.split(text, "\n")
    last = List.last(lines)

    fences =
      Enum.count(lines, &(&1 |> String.trim_leading() |> String.starts_with?(["```", "~~~"])))

    String.match?(text, ~r/[.!?…:;,)\]}"'»”’]$/u) or rem(fences, 2) == 1 or
      String.starts_with?(String.trim_leading(last), ["```", "~~~"]) or
      String.starts_with?(last, ["    ", "\t"])
  end

  defp open_new(author, topic, text, now, opts) do
    id = Federation.generate_id()
    window = window_seconds(topic)
    timer_from = timer_from(opts[:started_at] || typing_started(author, topic), now)

    message = %Message{
      id: id,
      uri: Federation.uri(:message, id),
      topic_id: topic.id,
      author_id: author.id,
      # Checked already (`quotes/3`).
      reply_to_id: opts[:reply_to_id],
      forwarded_from_id: opts[:forwarded_from_id],
      state: "open",
      opened_at: now,
      timer_from: timer_from,
      closes_at: Enum.max([DateTime.add(timer_from, window, :second), now], DateTime),
      body_md: text,
      body_html: Body.to_html(text, author: author, category_id: topic.category_id)
    }

    with {:ok, message} <- Repo.insert(message),
         {:ok, _} <- touch_topic(topic, now, 1),
         {:ok, _} <- Idejo.Reading.auto_follow(author.id, topic.id),
         # NO-02: a growing message notifies once, when it opens.
         {:ok, _} <- Notifications.notify_new(message, topic),
         {:ok, _} <- activity(author, message, "create", topic.uri) do
      {:ok, message}
    end
  end

  # When the author started typing (steward request, 2026-11-09), as the caller saw it on the
  # server's clock; never later than now. Without one, from the first commit.
  defp timer_from(%DateTime{} = started_at, now) do
    if DateTime.compare(started_at, now) == :gt, do: now, else: started_at
  end

  defp timer_from(_started_at, now), do: now

  # Forward: a message the author may read (a topic they may view, or a private conversation
  # of theirs), and may forward (`Forwards.may_forward?/2`: not deleted, their own only once
  # closed).
  defp forwarded_from(_author, blank) when blank in [nil, ""], do: nil

  defp forwarded_from(author, id) do
    with %Message{id: id} = message <- Forum.get_readable_message(author, id),
         true <- Forum.Forwards.may_forward?(author, message) do
      id
    else
      _ -> nil
    end
  end

  defp reply_to(_topic, blank) when blank in [nil, ""], do: nil

  defp reply_to(topic, id) do
    case Forum.get_topic_message(topic, id) do
      %Message{id: id, deleted_at: nil} -> id
      _ -> nil
    end
  end

  defp append(open, text, now, break?) do
    changed? = text != open.body_md

    # Changing text already sent keeps what was there (GM-11); adding at the end does not.
    edit? = changed? and not String.starts_with?(text, open.body_md)

    with {:ok, _} <- if(edit?, do: keep_version(open, now), else: {:ok, nil}),
         {:ok, message} <- update_body(open, text, changed?, edit?),
         {:ok, _} <- if(changed?, do: touch_topic(open.topic_id, now, 0), else: {:ok, nil}),
         {:ok, _} <- if(changed?, do: notify_mentions(message), else: {:ok, 0}) do
      cond do
        not break? -> {:ok, message}
        may_start_new?(message, now) -> close_locked(message, now)
        # Ctrl+Enter while the timers run (steward request, 2026-11-09): committed now, the
        # author's next message waiting for them (`held_until/3`).
        true -> close_locked(message, now, held: true)
      end
    end
  end

  # NO-02: an append notifies only someone newly @mentioned.
  defp notify_mentions(message),
    do: Notifications.notify_mentions(message, Repo.get!(Topic, message.topic_id))

  defp keep_version(message, now) do
    Repo.insert(%Version{message_id: message.id, body_md: message.body_md, created_at: now})
  end

  defp update_body(message, _text, false, _edit?), do: {:ok, message}

  defp update_body(message, text, true, edit?) do
    message
    |> Ecto.Changeset.change(
      body_md: text,
      body_html: Body.to_html(text, Body.context(message)),
      edited: message.edited or edit?
    )
    |> Repo.update()
  end

  defp touch_topic(%Topic{} = topic, now, added), do: touch_topic(topic.id, now, added)

  defp touch_topic(topic_id, now, added) do
    {1, _} =
      Repo.update_all(from(t in Topic, where: t.id == ^topic_id),
        set: [last_activity_at: now],
        inc: [message_count: added]
      )

    {:ok, topic_id}
  end

  @doc "Returns true when the message's window has ended (GM-03)."
  @spec window_ended?(Message.t(), DateTime.t()) :: boolean()
  def window_ended?(%Message{closes_at: closes_at}, now \\ DateTime.utc_now()),
    do: DateTime.compare(now, closes_at) != :lt

  @doc """
  Whether Ctrl+Enter completes the author's open message, so what follows starts a new one
  (GM-05): once its window has ended, and, while nobody has written below it, once it is
  `gm_unanswered_minutes` old (steward decision, 2026-10-23). Until then Ctrl+Enter is an
  Enter on a new line: a lone author keeps one message.

  A message in a private conversation (steward decision, 2026-10-27) has no unanswered
  message time either. A message opened with a window of 0 s elsewhere (the setting's
  minimum) still waits for it.
  """
  @spec may_start_new?(Message.t(), DateTime.t()) :: boolean()
  def may_start_new?(%Message{} = message, now \\ DateTime.utc_now()) do
    # `start_new_at/3`, asking the database whether it was answered only when that matters.
    not DateTime.before?(now, start_new_at(message, false, unanswered_seconds())) or
      (window_ended?(message, now) and (answered?(message) or private_topic?(message)))
  end

  @doc "Whether the message opened with no window (a private conversation, or a 0 s window)."
  @spec no_window?(Message.t()) :: boolean()
  def no_window?(%Message{opened_at: opened_at, closes_at: closes_at}),
    do: DateTime.compare(opened_at, closes_at) == :eq

  defp private_topic?(%Message{topic_id: topic_id}),
    do: Repo.exists?(from t in Topic, where: t.id == ^topic_id and t.private)

  @doc "When a message nobody wrote below may be completed by Ctrl+Enter (GM-05)."
  @spec unanswered_until(Message.t()) :: DateTime.t()
  def unanswered_until(%Message{} = message),
    do: DateTime.add(timer_start(message), unanswered_seconds(), :second)

  @doc """
  When a message's patience timers started: when its author started typing it (steward
  request, 2026-11-09), or for older messages its first commit.
  """
  @spec timer_start(Message.t()) :: DateTime.t()
  def timer_start(%Message{timer_from: %DateTime{} = from}), do: from
  def timer_start(%Message{opened_at: opened_at}), do: opened_at

  @doc "The unanswered message time (`gm_unanswered_minutes`, decimals allowed) in seconds."
  @spec unanswered_seconds() :: non_neg_integer()
  def unanswered_seconds, do: round(Settings.get(:gm_unanswered_minutes) * 60)

  # Someone wrote below it: a message opened after it, not deleted.
  defp answered?(message) do
    Repo.exists?(
      from m in Message,
        where:
          m.topic_id == ^message.topic_id and m.id != ^message.id and is_nil(m.deleted_at) and
            (m.opened_at > ^message.opened_at or
               (m.opened_at == ^message.opened_at and m.id > ^message.id))
    )
  end

  @doc """
  Closes an open message: Ctrl+Enter after the window (GM-05), a session gone for good (GM-12)
  or a moderator (GM-16); lock and archive use `close_open_in_topics/1`. Closing a closed
  message changes nothing.
  """
  @spec close(Message.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def close(%Message{} = message) do
    result =
      Repo.transact(fn ->
        message = Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE")

        if message.state == "open",
          do: close_locked(message, DateTime.utc_now()),
          else: {:ok, message}
      end)

    with {:ok, message} <- result, do: after_commit(message)
    result
  end

  defp close_locked(message, now, fields \\ []) do
    with {:ok, message} <-
           message
           |> Ecto.Changeset.change([state: "closed", closed_at: now] ++ fields)
           |> Repo.update(),
         {:ok, _} <- activity_for_close(message) do
      {:ok, message}
    end
  end

  defp activity_for_close(message) do
    author = Repo.get!(User, message.author_id)
    activity(author, message, "update", topic_uri(message))
  end

  defp topic_uri(message),
    do: Repo.one!(from t in Topic, where: t.id == ^message.topic_id, select: t.uri)

  defp activity(author, message, verb, topic_uri) do
    Repo.insert(
      Federation.activity_changeset(%{
        actor_uri: author.uri,
        verb: verb,
        object_uri: message.uri,
        target_uri: topic_uri,
        payload: %{"type" => "Note", "state" => message.state}
      })
    )
  end

  # After the transaction: the timer follows the state, then readers hear of it.
  defp after_commit(%Message{state: "open"} = message) do
    OpenMessage.start(message)
    broadcast(message.topic_id, {:message, message})
  end

  defp after_commit(%Message{} = message) do
    OpenMessage.stop(message.id)
    broadcast(message.topic_id, {:message, message})
  end

  @doc """
  Edits a message, as its author (GM-10): the way to change a message once it has closed;
  an open message is edited in place in the composer, through `commit/4`.

  Changing text already there keeps the previous text as a version and marks the message
  edited (GM-11); adding text at the end is not an edit and keeps no version (TP-05). The text
  is kept as written: no `.` is added, as it is not an Enter. Then the message is broadcast.

  Refused with `{:error, :forbidden}` for someone else's message, an open one, or in a locked or
  archived topic; `{:error, :blank}` for empty text.

  ## Options

    * `:version` - `:auto` (the default) as above; `:always` keeps the previous text as a
      version whenever the text changes, appends too; `:never` keeps none. Editing in the
      composer (steward decision, 2026-10-24) keeps one version per edit: `:always` for
      its first change, `:never` for the Enters after it.
  """
  @spec edit(User.t(), Message.t(), String.t(), keyword()) ::
          {:ok, Message.t()} | {:error, :forbidden | :blank | Ecto.Changeset.t()}
  def edit(%User{} = author, %Message{} = message, text, opts \\ []) when is_binary(text) do
    text = String.trim_trailing(text)

    result =
      Repo.transact(fn ->
        message = Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE")
        topic = Repo.get!(Topic, message.topic_id)

        cond do
          message.author_id != author.id -> {:error, :forbidden}
          message.deleted_at != nil -> {:error, :forbidden}
          message.state != "closed" -> {:error, :forbidden}
          not Forum.can_post?(author, topic) -> {:error, :forbidden}
          String.trim(text) == "" -> {:error, :blank}
          text == message.body_md -> {:ok, message}
          true -> save_edit(author, message, text, topic, Keyword.get(opts, :version, :auto))
        end
      end)

    with {:ok, message} <- result, do: broadcast(message.topic_id, {:message, message})
    result
  end

  @doc """
  Saves an edit of a closed message made in the message editor: the author's own edit
  (`edit/4`, GM-10), or someone else's message edited as a moderator of its category
  (`edit_as_moderator/4`, MO-02, logged with the optional `reason`). Each refuses on its own.
  """
  @spec save_edit(User.t(), Message.t(), String.t(), String.t() | nil) ::
          {:ok, Message.t()} | {:error, atom() | Ecto.Changeset.t()}
  def save_edit(%User{id: id} = actor, %Message{author_id: id} = message, text, _reason),
    do: edit(actor, message, text)

  def save_edit(%User{} = actor, %Message{} = message, text, reason),
    do: edit_as_moderator(actor, message, text, reason)

  @doc """
  Deletes a message, as its author (steward decision, 2026-10-23): asked for when an edit
  leaves no text. Like a moderator's delete (MO-02), the message stays with its text and
  versions for moderators, readers see "Message deleted by user" (`deleted_by_author?/1`),
  and search, notifications and unread counts leave it out; the topic counts one message
  less, with a `delete` activity (FD-02). Not logged: no moderator acted.

  Refused like `edit/3` (`{:error, :forbidden}`: someone else's, open, deleted, or a topic
  that takes no messages), and for the topic's opening message (`{:error, :opening}`), which
  the topic needs.
  """
  @spec delete_own(User.t(), Message.t()) ::
          {:ok, Message.t()} | {:error, :forbidden | :opening | Ecto.Changeset.t()}
  def delete_own(%User{} = author, %Message{} = message) do
    result =
      Repo.transact(fn ->
        message = Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE")
        topic = Repo.get!(Topic, message.topic_id)

        cond do
          message.author_id != author.id -> {:error, :forbidden}
          message.deleted_at != nil -> {:error, :forbidden}
          message.state != "closed" -> {:error, :forbidden}
          not Forum.can_post?(author, topic) -> {:error, :forbidden}
          opening?(message) -> {:error, :opening}
          true -> delete_by_author(author, message, topic)
        end
      end)

    with {:ok, message} <- result, do: broadcast(message.topic_id, {:message, message})
    result
  end

  @spoiler_label_max 100

  @doc """
  Marks the author's message as a spoiler, or no longer one (`!spoiler`, steward decision,
  2026-10-23): readers see it blurred until they choose Reveal. Not an edit: no version is
  kept. Refused like `edit/3`, but open messages are marked too (the composer's).

  `label` (`!spoiler:overlay text:`, steward decision, 2026-10-28) is what the cover says,
  trimmed and cut at #{@spoiler_label_max} characters; a blank one is none. It goes with the
  spoiler: no longer one, it has none.
  """
  @spec set_spoiler(User.t(), Message.t(), boolean(), String.t() | nil) ::
          {:ok, Message.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def set_spoiler(%User{} = author, %Message{} = message, spoiler?, label \\ nil)
      when is_boolean(spoiler?) do
    label = if spoiler?, do: spoiler_label(label)

    result =
      Repo.transact(fn ->
        message = Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE")
        topic = Repo.get!(Topic, message.topic_id)

        cond do
          message.author_id != author.id -> {:error, :forbidden}
          message.deleted_at != nil -> {:error, :forbidden}
          not Forum.can_post?(author, topic) -> {:error, :forbidden}
          message.spoiler == spoiler? and message.spoiler_label == label -> {:ok, message}
          true -> save_spoiler(author, message, spoiler?, label, topic)
        end
      end)

    with {:ok, message} <- result, do: broadcast(message.topic_id, {:message, message})
    result
  end

  defp spoiler_label(nil), do: nil

  defp spoiler_label(label) when is_binary(label) do
    case label |> String.trim() |> String.slice(0, @spoiler_label_max) do
      "" -> nil
      label -> label
    end
  end

  defp save_spoiler(author, message, spoiler?, label, topic) do
    with {:ok, message} <-
           message
           |> Ecto.Changeset.change(spoiler: spoiler?, spoiler_label: label)
           |> Repo.update(),
         {:ok, _} <- activity(author, message, "update", topic.uri) do
      {:ok, message}
    end
  end

  @doc """
  The name a message is shown under: its author's, or for the opening message of a topical
  topic (Topic Type, steward request, 2026-11-07; `anonymous`), "the topic", so the starter
  never shows. The author must be loaded for others.
  """
  @spec author_name(Message.t()) :: String.t()
  def author_name(%Message{anonymous: true}),
    do: gettext("the topic")

  def author_name(%Message{author: author}), do: author.display_name

  @doc "Whether a deleted message was deleted by its author rather than by a moderator."
  @spec deleted_by_author?(Message.t()) :: boolean()
  def deleted_by_author?(%Message{deleted_at: nil}), do: false
  def deleted_by_author?(%Message{} = message), do: message.deleted_by_id == message.author_id

  defp opening?(message) do
    first =
      Repo.one(
        from m in Message,
          where: m.topic_id == ^message.topic_id,
          order_by: [asc: m.opened_at, asc: m.id],
          limit: 1,
          select: m.id
      )

    first == message.id
  end

  defp delete_by_author(author, message, topic) do
    with {:ok, message} <-
           message
           |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(), deleted_by_id: author.id)
           |> Repo.update(),
         {1, _} <-
           Repo.update_all(from(t in Topic, where: t.id == ^topic.id),
             inc: [message_count: -1]
           ),
         {:ok, _} <- activity(author, message, "delete", topic.uri) do
      {:ok, message}
    end
  end

  defp save_edit(author, message, text, topic, version) do
    now = DateTime.utc_now()

    edit? =
      case version do
        :auto -> not String.starts_with?(text, message.body_md)
        :always -> true
        :never -> false
      end

    with {:ok, _} <- if(edit?, do: keep_version(message, now), else: {:ok, nil}),
         {:ok, message} <- update_body(message, text, true, edit?),
         {:ok, _} <- Notifications.notify_mentions(message, topic),
         {:ok, _} <- activity(author, message, "update", topic.uri) do
      {:ok, message}
    end
  end

  @doc """
  Closes every open message in the given topics, inside the caller's transaction: for a topic
  that is locked or archived (GM-12). Returns the closed messages; once the transaction has
  committed, pass them to `announce_closed/1`.
  """
  @spec close_open_in_topics([Ecto.UUID.t()]) :: [Message.t()]
  def close_open_in_topics(topic_ids) do
    now = DateTime.utc_now()

    from(m in Message, where: m.topic_id in ^topic_ids and m.state == "open", lock: "FOR UPDATE")
    |> Repo.all()
    |> Enum.map(fn message ->
      {:ok, closed} = close_locked(message, now)
      closed
    end)
  end

  @doc "Stops the timers of closed messages and tells their topics' viewers (after commit)."
  @spec announce_closed([Message.t()]) :: :ok
  def announce_closed(messages), do: Enum.each(messages, &after_commit/1)

  @doc """
  Closes the author's open message in a topic, if any: when their session has been gone for
  longer than the grace (GM-12, `Idejo.Messages.Authors`).
  """
  @spec close_for_author(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Message.t() | nil}
  def close_for_author(topic_id, author_id) do
    case Repo.one(
           from m in Message,
             where: m.topic_id == ^topic_id and m.author_id == ^author_id and m.state == "open"
         ) do
      nil -> {:ok, nil}
      message -> close(message)
    end
  end

  @doc """
  Closes another user's open message, as a moderator: someone with the `:moderate` right in
  the topic's category (GM-16). `{:error, :forbidden}` otherwise. The action goes in the
  moderation log (MO-03) with the optional `reason`, in the same transaction.
  """
  @spec close_as_moderator(User.t(), Message.t(), String.t() | nil) ::
          {:ok, Message.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def close_as_moderator(%User{} = moderator, %Message{} = message, reason \\ nil) do
    topic = Topic |> Repo.get!(message.topic_id) |> Repo.preload(:category)

    if Idejo.Access.can?(moderator, :moderate, topic) do
      result =
        Repo.transact(fn ->
          message = Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE")
          close_logged(moderator, message, reason)
        end)

      with {:ok, message} <- result, do: after_commit(message)
      result
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Pins or unpins a message (steward request, 2026-11-13), as someone with `:moderate` in its
  topic: pinned messages are listed in the topic navigator (`Idejo.Forum.pinned_messages/1`),
  oldest pin first. Not in private conversations, not deleted ones. Logged `message.pin` or
  `message.unpin` (MO-03); then the topic gets the message and `{:pins_changed, topic_id}`.
  """
  @spec set_pinned(User.t(), Message.t(), boolean()) ::
          {:ok, Message.t()} | {:error, :forbidden | :deleted | Ecto.Changeset.t()}
  def set_pinned(%User{} = moderator, %Message{} = message, pinned) when is_boolean(pinned) do
    topic = Repo.get!(Topic, message.topic_id)

    cond do
      topic.private or not Idejo.Access.can?(moderator, :moderate, topic) ->
        {:error, :forbidden}

      pinned and message.deleted_at != nil ->
        {:error, :deleted}

      true ->
        result = Repo.transact(fn -> pin_locked(moderator, message.id, pinned) end)

        with {:ok, message} <- result do
          broadcast(message.topic_id, {:message, message})
          broadcast(message.topic_id, {:pins_changed, message.topic_id})
        end

        result
    end
  end

  defp pin_locked(moderator, id, pinned) do
    message = Repo.one!(from m in Message, where: m.id == ^id, lock: "FOR UPDATE")

    if (message.pinned_at != nil) == pinned do
      {:ok, message}
    else
      at = if pinned, do: DateTime.utc_now()
      action = if pinned, do: "message.pin", else: "message.unpin"

      with {:ok, message} <- message |> Ecto.Changeset.change(pinned_at: at) |> Repo.update(),
           {:ok, _} <- Moderation.record(moderator, action, message) do
        {:ok, message}
      end
    end
  end

  @doc """
  Closes an open message as a moderator inside the caller's transaction, logged like
  `close_as_moderator/3` (the caller checks the right and locks the row): for moving it to
  another topic (TP-15). Pass the closed message to `announce_closed/1` after the commit.
  """
  @spec close_logged_in_transaction(User.t(), Message.t(), String.t() | nil) ::
          {:ok, Message.t()} | {:error, term()}
  def close_logged_in_transaction(moderator, message, reason),
    do: close_logged(moderator, message, reason)

  # A message that closed meanwhile stays as it is, and nothing is logged.
  defp close_logged(_moderator, %Message{state: "closed"} = message, _reason), do: {:ok, message}

  defp close_logged(moderator, message, reason) do
    with {:ok, message} <- close_locked(message, DateTime.utc_now()),
         {:ok, _} <- Moderation.record(moderator, "message.close", message, reason: reason) do
      {:ok, message}
    end
  end

  @doc """
  Deletes a message, as a moderator of its topic's category (MO-02), with an optional
  reason. The message stays, with its text and versions, for moderators (steward decision):
  readers see a placeholder, and search, notifications and unread counts leave it out. An
  open message is closed first. The topic counts one message less, the message's open reports
  are resolved, and the moderation log records it (MO-03), in one transaction; then the
  message is broadcast. Deleting a deleted message does nothing.
  """
  @spec delete_as_moderator(User.t(), Message.t(), String.t() | nil) ::
          {:ok, Message.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def delete_as_moderator(%User{} = moderator, %Message{} = message, reason \\ nil) do
    as_moderator(moderator, message, fn locked -> delete_logged(moderator, locked, reason) end)
  end

  @doc """
  Deletes a reported message of a private conversation, as a server moderator, from the
  report queue (steward decision, 2026-10-27): there is no category to moderate and no way
  into the conversation, so only a message with open reports, which it resolves. Otherwise
  like `delete_as_moderator/3`: the text stays for moderators, the participants see the
  placeholder, logged (MO-03), then broadcast. `{:error, :forbidden}` for anyone else, a
  message of a topic, or one without open reports.
  """
  @spec delete_reported_private(User.t(), Message.t(), String.t() | nil) ::
          {:ok, Message.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def delete_reported_private(%User{} = moderator, %Message{} = message, reason \\ nil) do
    topic = Repo.get!(Topic, message.topic_id)

    if topic.private and Idejo.Access.server_moderator?(moderator) do
      result = Repo.transact(fn -> delete_if_reported(moderator, message, reason) end)
      with {:ok, message} <- result, do: after_commit(message)
      result
    else
      {:error, :forbidden}
    end
  end

  defp delete_if_reported(moderator, message, reason) do
    locked = Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE")

    if Moderation.open_reports?(locked),
      do: delete_logged(moderator, locked, reason),
      else: {:error, :forbidden}
  end

  @doc """
  Deletes several messages of one topic at once, as a moderator of its category (MO-02;
  steward decision, 2026-10-23: "Select multiple messages for deletion"). Each is deleted
  like `delete_as_moderator/3`, all in one transaction, and logged one by one (MO-03); then
  each is broadcast. The moderator's own messages and those of other topics are left out
  (`{:error, :none}` when nothing is left); deleted ones do nothing. Returns the deleted
  messages.
  """
  @spec delete_many_as_moderator(User.t(), Topic.t(), [Ecto.UUID.t()], String.t() | nil) ::
          {:ok, [Message.t()]} | {:error, :forbidden | :none | Ecto.Changeset.t()}
  def delete_many_as_moderator(%User{} = moderator, %Topic{} = topic, ids, reason \\ nil)
      when is_list(ids) do
    topic = Repo.preload(topic, :category)

    if Idejo.Access.can?(moderator, :moderate, topic) do
      result =
        Repo.transact(fn ->
          # Locked in id order, so two moderators never wait on each other.
          from(m in Message,
            where: m.topic_id == ^topic.id and m.id in ^ids and m.author_id != ^moderator.id,
            order_by: m.id,
            lock: "FOR UPDATE"
          )
          |> Repo.all()
          |> delete_each(moderator, reason)
        end)

      with {:ok, messages} <- result, do: Enum.each(messages, &after_commit/1)
      result
    else
      {:error, :forbidden}
    end
  end

  defp delete_each([], _moderator, _reason), do: {:error, :none}

  defp delete_each(messages, moderator, reason) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, done} ->
      case delete_logged(moderator, message, reason) do
        {:ok, message} -> {:cont, {:ok, [message | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  @doc """
  Edits someone's closed message, as a moderator of its category (MO-02), with an optional
  reason. Like an author's edit (GM-10, GM-11): changing text keeps the earlier version,
  which moderators can see (MO-06). Open messages are closed first by the moderator
  (`{:error, :open}`), deleted ones are not edited (`{:error, :deleted}`), and a blank text is
  refused (`{:error, :blank}`). Logged (MO-03); then broadcast.
  """
  @spec edit_as_moderator(User.t(), Message.t(), String.t(), String.t() | nil) ::
          {:ok, Message.t()}
          | {:error, :forbidden | :open | :deleted | :blank | Ecto.Changeset.t()}
  def edit_as_moderator(%User{} = moderator, %Message{} = message, text, reason \\ nil)
      when is_binary(text) do
    text = String.trim_trailing(text)

    as_moderator(moderator, message, fn locked ->
      cond do
        locked.deleted_at -> {:error, :deleted}
        locked.state == "open" -> {:error, :open}
        String.trim(text) == "" -> {:error, :blank}
        text == locked.body_md -> {:ok, locked}
        true -> moderator_edit(moderator, locked, text, reason)
      end
    end)
  end

  # Checks the moderate right, runs `fun` on the locked message in a transaction, and
  # announces the result once committed.
  defp as_moderator(moderator, message, fun) do
    topic = Topic |> Repo.get!(message.topic_id) |> Repo.preload(:category)

    if Idejo.Access.can?(moderator, :moderate, topic) do
      result =
        Repo.transact(fn ->
          fun.(Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE"))
        end)

      with {:ok, message} <- result, do: after_commit(message)
      result
    else
      {:error, :forbidden}
    end
  end

  defp delete_logged(_moderator, %Message{deleted_at: %DateTime{}} = message, _reason),
    do: {:ok, message}

  defp delete_logged(moderator, message, reason) do
    now = DateTime.utc_now()

    with {:ok, message} <-
           if(message.state == "open", do: close_locked(message, now), else: {:ok, message}),
         {:ok, message} <-
           message
           |> Ecto.Changeset.change(deleted_at: now, deleted_by_id: moderator.id)
           |> Repo.update(),
         {1, _} <-
           Repo.update_all(from(t in Topic, where: t.id == ^message.topic_id),
             inc: [message_count: -1]
           ),
         {_, _} <- Moderation.resolve_reports_of(moderator, message),
         {:ok, _} <- Moderation.record(moderator, "message.delete", message, reason: reason),
         {:ok, _} <- activity(moderator, message, "delete", topic_uri(message)) do
      {:ok, message}
    end
  end

  defp moderator_edit(moderator, message, text, reason) do
    now = DateTime.utc_now()
    edit? = not String.starts_with?(text, message.body_md)
    topic_uri = topic_uri(message)

    with {:ok, _} <- if(edit?, do: keep_version(message, now), else: {:ok, nil}),
         {:ok, message} <- update_body(message, text, true, edit?),
         {:ok, message} <- mark_moderator_edited(message),
         {:ok, _} <- Moderation.record(moderator, "message.edit", message, reason: reason),
         {:ok, _} <- activity(moderator, message, "update", topic_uri) do
      {:ok, message}
    end
  end

  # Readers see "message edited by a moderator" from now on (steward request, 2026-11-09).
  defp mark_moderator_edited(%Message{moderator_edited: true} = message), do: {:ok, message}

  defp mark_moderator_edited(message),
    do: message |> Ecto.Changeset.change(moderator_edited: true) |> Repo.update()

  @doc "Lists a message's earlier versions, oldest first (GM-11)."
  @spec list_versions(Message.t()) :: [Version.t()]
  def list_versions(%Message{id: id}) do
    Repo.all(from v in Version, where: v.message_id == ^id, order_by: [asc: v.created_at])
  end
end
