# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages do
  @moduledoc """
  The growing-message engine (GM, CLAUDE.md "Growing-message invariants").

  The composer sends the author's whole message as it reads after each Enter: `commit/4`
  stores it, in the database first (NF-02), and only then acknowledges and broadcasts it.

    * With no open message in the topic, Enter opens one (GM-01). Its window is fixed now:
      `closes_at = opened_at + window` (GM-03).
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

  alias Idejo.Accounts.User
  alias Idejo.Federation
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages.{Body, Message, OpenMessage, Version}
  alias Idejo.Moderation
  alias Idejo.Notifications
  alias Idejo.RateLimit
  alias Idejo.Repo
  alias Idejo.Settings

  @shown [:author, :versions, reply_to: :author]
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
  rather than by each of the topic's viewers (NF-01). Call it once the message's transaction
  has committed: it also announces the notifications written with it
  (`Idejo.Notifications.announce/1`).
  """
  @spec broadcast(Ecto.UUID.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic_id, {:message, %Message{} = message}) do
    message = Repo.preload(message, @shown, force: true)
    # Committed: the notifications written with it go out live too.
    :ok = Notifications.announce(message)
    Phoenix.PubSub.broadcast(@pubsub, "topic:" <> topic_id, {:message, message})
  end

  def broadcast(topic_id, event),
    do: Phoenix.PubSub.broadcast(@pubsub, "topic:" <> topic_id, event)

  @doc "What a topic view shows of a message besides its own fields, for `Repo.preload/2`."
  @spec shown() :: list()
  def shown, do: @shown

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
      # The open message closed for the new one: announced first, so viewers see it end.
      {:ok, {closed, message}} ->
        after_commit(closed)
        after_commit(message)
        {:ok, message}

      {:ok, %Message{} = message} ->
        after_commit(message)
        result

      result ->
        result
    end
  end

  defp commit_locked(author, topic, text, opts) do
    open = open_message(author, topic)
    now = DateTime.utc_now()

    cond do
      open == nil and text == "" ->
        {:ok, nil}

      open != nil and opts[:new] == true ->
        start_over(author, topic, open, text, now, opts[:reply_to_id])

      # SP-05: and a new message counts towards the new messages a minute.
      open == nil ->
        with :ok <- RateLimit.check(:new_message, author.id),
             do: open_new(author, topic, text, now, opts[:reply_to_id])

      true ->
        append(open, text, now, Keyword.get(opts, :break, false))
    end
  end

  # A new message while one is open (`:new`): the open one closes first (GM-09: one open).
  defp start_over(_author, _topic, _open, "", _now, _reply_to_id), do: {:ok, nil}

  defp start_over(author, topic, open, text, now, reply_to_id) do
    early? = reply_to_id not in [nil, ""] and Settings.get(:gm_early_reply)

    with :ok <- if(early? or may_start_new?(open, now), do: :ok, else: {:error, :too_soon}),
         :ok <- RateLimit.check(:new_message, author.id),
         {:ok, closed} <- close_locked(open, now),
         {:ok, message} <- open_new(author, topic, text, now, reply_to_id) do
      {:ok, {closed, message}}
    end
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

  defp open_new(author, topic, text, now, reply_to_id) do
    id = Federation.generate_id()
    window = Settings.get(:gm_window_seconds)

    message = %Message{
      id: id,
      uri: Federation.uri(:message, id),
      topic_id: topic.id,
      author_id: author.id,
      reply_to_id: reply_to(topic, reply_to_id),
      state: "open",
      opened_at: now,
      closes_at: DateTime.add(now, window, :second),
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

  defp reply_to(_topic, blank) when blank in [nil, ""], do: nil

  defp reply_to(topic, id) do
    case Forum.get_topic_message(topic, id) do
      %Message{id: id} -> id
      nil -> nil
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
      if break? and may_start_new?(message, now),
        do: close_locked(message, now),
        else: {:ok, message}
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
  """
  @spec may_start_new?(Message.t(), DateTime.t()) :: boolean()
  def may_start_new?(%Message{} = message, now \\ DateTime.utc_now()) do
    window_ended?(message, now) and
      (DateTime.compare(now, unanswered_until(message)) != :lt or answered?(message))
  end

  @doc "When a message nobody wrote below may be completed by Ctrl+Enter (GM-05)."
  @spec unanswered_until(Message.t()) :: DateTime.t()
  def unanswered_until(%Message{opened_at: opened_at}),
    do: DateTime.add(opened_at, Settings.get(:gm_unanswered_minutes) * 60, :second)

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

  defp close_locked(message, now) do
    with {:ok, message} <-
           message |> Ecto.Changeset.change(state: "closed", closed_at: now) |> Repo.update(),
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

  @doc """
  Marks the author's message as a spoiler, or no longer one (`!spoiler`, steward decision,
  2026-10-23): readers see it blurred until they choose Reveal. Not an edit: no version is
  kept. Refused like `edit/3`, but open messages are marked too (the composer's).
  """
  @spec set_spoiler(User.t(), Message.t(), boolean()) ::
          {:ok, Message.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def set_spoiler(%User{} = author, %Message{} = message, spoiler?) when is_boolean(spoiler?) do
    result =
      Repo.transact(fn ->
        message = Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE")
        topic = Repo.get!(Topic, message.topic_id)

        cond do
          message.author_id != author.id -> {:error, :forbidden}
          message.deleted_at != nil -> {:error, :forbidden}
          not Forum.can_post?(author, topic) -> {:error, :forbidden}
          message.spoiler == spoiler? -> {:ok, message}
          true -> save_spoiler(author, message, spoiler?, topic)
        end
      end)

    with {:ok, message} <- result, do: broadcast(message.topic_id, {:message, message})
    result
  end

  defp save_spoiler(author, message, spoiler?, topic) do
    with {:ok, message} <- message |> Ecto.Changeset.change(spoiler: spoiler?) |> Repo.update(),
         {:ok, _} <- activity(author, message, "update", topic.uri) do
      {:ok, message}
    end
  end

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

    if Idejo.Access.can?(moderator, :moderate, topic.category) do
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

    if Idejo.Access.can?(moderator, :moderate, topic.category) do
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

    if Idejo.Access.can?(moderator, :moderate, topic.category) do
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
         {:ok, _} <- Moderation.record(moderator, "message.edit", message, reason: reason),
         {:ok, _} <- activity(moderator, message, "update", topic_uri) do
      {:ok, message}
    end
  end

  @doc "Lists a message's earlier versions, oldest first (GM-11)."
  @spec list_versions(Message.t()) :: [Version.t()]
  def list_versions(%Message{id: id}) do
    Repo.all(from v in Version, where: v.message_id == ^id, order_by: [asc: v.created_at])
  end
end
