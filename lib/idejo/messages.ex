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
  Closes an open message (GM-05; lock, archive, disconnect and moderators come with GM-12 and
  GM-16). Closing a closed message changes nothing.
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

  @doc "Lists a message's earlier versions, oldest first (GM-11)."
  @spec list_versions(Message.t()) :: [Version.t()]
  def list_versions(%Message{id: id}) do
    Repo.all(from v in Version, where: v.message_id == ^id, order_by: [asc: v.created_at])
  end
end
