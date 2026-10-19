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
  after it). A commit that changes text already sent keeps the previous full text as a
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
  alias Idejo.Messages.{Message, OpenMessage, Version}
  alias Idejo.Repo
  alias Idejo.Settings

  @pubsub Idejo.PubSub

  @doc "Subscribes the caller to a topic's message events."
  @spec subscribe(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe(topic_id), do: Phoenix.PubSub.subscribe(@pubsub, "topic:" <> topic_id)

  @doc "Unsubscribes the caller from a topic's message events."
  @spec unsubscribe(Ecto.UUID.t()) :: :ok
  def unsubscribe(topic_id), do: Phoenix.PubSub.unsubscribe(@pubsub, "topic:" <> topic_id)

  @doc "Broadcasts a message event on a topic."
  @spec broadcast(Ecto.UUID.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic_id, event),
    do: Phoenix.PubSub.broadcast(@pubsub, "topic:" <> topic_id, event)

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
  """
  @spec commit(User.t(), Topic.t(), String.t(), keyword()) ::
          {:ok, Message.t() | nil} | {:error, :forbidden | Ecto.Changeset.t()}
  def commit(%User{} = author, %Topic{} = topic, text, opts \\ []) when is_binary(text) do
    result =
      Repo.transact(fn ->
        # Locked, so the open message and the topic's state cannot change under this commit.
        topic = Repo.one!(from t in Topic, where: t.id == ^topic.id, lock: "FOR UPDATE")

        if Forum.can_post?(author, topic),
          do: commit_locked(author, topic, normalize(text), opts),
          else: {:error, :forbidden}
      end)

    with {:ok, %Message{} = message} <- result do
      after_commit(message)
    end

    result
  end

  defp commit_locked(author, topic, text, opts) do
    open = open_message(author, topic)
    now = DateTime.utc_now()

    cond do
      open == nil and text == "" -> {:ok, nil}
      open == nil -> open_new(author, topic, text, now, opts[:reply_to_id])
      true -> append(open, text, now, Keyword.get(opts, :break, false))
    end
  end

  # The text as sent: line ends trimmed, and a `.` after text that ends without punctuation.
  defp normalize(text) do
    text = String.trim_trailing(text)
    if text == "" or ends_in_punctuation?(text), do: text, else: text <> "."
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
      body_html: Idejo.Markdown.to_html(text)
    }

    with {:ok, message} <- Repo.insert(message),
         {:ok, _} <- touch_topic(topic, now, 1),
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
         {:ok, _} <- if(changed?, do: touch_topic(open.topic_id, now, 0), else: {:ok, nil}) do
      if break? and window_ended?(message, now),
        do: close_locked(message, now),
        else: {:ok, message}
    end
  end

  defp keep_version(message, now) do
    Repo.insert(%Version{message_id: message.id, body_md: message.body_md, created_at: now})
  end

  defp update_body(message, _text, false, _edit?), do: {:ok, message}

  defp update_body(message, text, true, edit?) do
    message
    |> Ecto.Changeset.change(
      body_md: text,
      body_html: Idejo.Markdown.to_html(text),
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
    topic_uri = Repo.one!(from t in Topic, where: t.id == ^message.topic_id, select: t.uri)
    activity(author, message, "update", topic_uri)
  end

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
  """
  @spec edit(User.t(), Message.t(), String.t()) ::
          {:ok, Message.t()} | {:error, :forbidden | :blank | Ecto.Changeset.t()}
  def edit(%User{} = author, %Message{} = message, text) when is_binary(text) do
    text = String.trim_trailing(text)

    result =
      Repo.transact(fn ->
        message = Repo.one!(from m in Message, where: m.id == ^message.id, lock: "FOR UPDATE")
        topic = Repo.get!(Topic, message.topic_id)

        cond do
          message.author_id != author.id -> {:error, :forbidden}
          message.state != "closed" -> {:error, :forbidden}
          not Forum.can_post?(author, topic) -> {:error, :forbidden}
          String.trim(text) == "" -> {:error, :blank}
          text == message.body_md -> {:ok, message}
          true -> save_edit(author, message, text, topic)
        end
      end)

    with {:ok, message} <- result, do: broadcast(message.topic_id, {:message, message})
    result
  end

  defp save_edit(author, message, text, topic) do
    now = DateTime.utc_now()
    edit? = not String.starts_with?(text, message.body_md)

    with {:ok, _} <- if(edit?, do: keep_version(message, now), else: {:ok, nil}),
         {:ok, message} <- update_body(message, text, true, edit?),
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
  the topic's category (GM-16). `{:error, :forbidden}` otherwise. The moderation log (MO-03)
  comes with M5.
  """
  @spec close_as_moderator(User.t(), Message.t()) ::
          {:ok, Message.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def close_as_moderator(%User{} = moderator, %Message{} = message) do
    topic = Topic |> Repo.get!(message.topic_id) |> Repo.preload(:category)

    if Idejo.Access.can?(moderator, :moderate, topic.category),
      do: close(message),
      else: {:error, :forbidden}
  end

  @doc "Lists a message's earlier versions, oldest first (GM-11)."
  @spec list_versions(Message.t()) :: [Version.t()]
  def list_versions(%Message{id: id}) do
    Repo.all(from v in Version, where: v.message_id == ^id, order_by: [asc: v.created_at])
  end
end
