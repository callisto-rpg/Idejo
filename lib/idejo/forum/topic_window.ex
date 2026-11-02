# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.TopicWindow do
  @moduledoc """
  Long topics, a window at a time (steward decision, 2026-11-01): a topic page loads the
  messages around where its reader lands, and more as they scroll, never the whole topic.

  Messages come in the topic's order (`opened_at`, then `id`: GM-08), read from the index on
  `(topic_id, opened_at)`: before or after a message (a cursor, so messages arriving or
  moving never shift a window), the first or the last ones, or a fixed page for readers
  without JavaScript and search engines (`?page=n`, AX-04, SE-04). How many is set by the
  "Performance" setting (`sizes/1`).
  """

  import Ecto.Query

  alias Idejo.Accounts.User
  alias Idejo.Forum.Topic
  alias Idejo.Messages.Message
  alias Idejo.Repo
  alias Idejo.Settings

  # What a topic view shows of each message, as Idejo.Forum.list_messages/1.
  @preload [:author, :versions, reply_to: :author]

  @normal %{before: 10, after: 30, step: 40, cap: 200, page: 50}

  @typedoc """
  `before` and `after`: messages loaded around the one a reader lands on; `step`: loaded at
  each scroll; `cap`: at most in a page at once (more only to keep the author's open
  message); `page`: per page without JavaScript.
  """
  @type sizes :: %{
          before: pos_integer(),
          after: pos_integer(),
          step: pos_integer(),
          cap: pos_integer(),
          page: pos_integer()
        }

  @doc """
  The sizes for a "Performance" setting: "normal" (#{inspect(@normal)}), "light" (half of
  each) or "heavy" (three times each). Without an argument, the server's setting.
  """
  @spec sizes(String.t()) :: sizes()
  def sizes(level \\ Settings.get(:performance))
  def sizes("light"), do: Map.new(@normal, fn {key, n} -> {key, div(n, 2)} end)
  def sizes("heavy"), do: Map.new(@normal, fn {key, n} -> {key, n * 3} end)
  def sizes(_normal), do: @normal

  @doc "The topic's first message, its opening one, or nil when it has none yet."
  @spec first(Topic.t()) :: Message.t() | nil
  def first(%Topic{id: id}) do
    from(m in Message,
      where: m.topic_id == ^id,
      order_by: [asc: m.opened_at, asc: m.id],
      limit: 1
    )
    |> Repo.one()
    |> then(&(&1 && hd(shown([&1]))))
  end

  @doc "The topic's latest message as `%{id: id, opened_at: opened_at}`, or nil."
  @spec latest(Topic.t()) :: %{id: Ecto.UUID.t(), opened_at: DateTime.t()} | nil
  def latest(%Topic{id: id}) do
    Repo.one(
      from m in Message,
        where: m.topic_id == ^id,
        order_by: [desc: m.opened_at, desc: m.id],
        limit: 1,
        select: %{id: m.id, opened_at: m.opened_at}
    )
  end

  @doc "The topic's last `n` messages, in order."
  @spec last(Topic.t(), non_neg_integer()) :: [Message.t()]
  def last(%Topic{id: id}, n) do
    from(m in Message,
      where: m.topic_id == ^id,
      order_by: [desc: m.opened_at, desc: m.id],
      limit: ^n
    )
    |> load_reversed()
  end

  @doc "The `n` messages before `message` in its topic, in order."
  @spec before(Topic.t(), Message.t(), non_neg_integer()) :: [Message.t()]
  def before(%Topic{id: id}, %Message{} = message, n) do
    from(m in Message,
      where: m.topic_id == ^id and m.opened_at <= ^message.opened_at,
      where: m.opened_at < ^message.opened_at or m.id < ^message.id,
      order_by: [desc: m.opened_at, desc: m.id],
      limit: ^n
    )
    |> load_reversed()
  end

  @doc "The `n` messages after `message` in its topic, in order."
  @spec next(Topic.t(), Message.t(), non_neg_integer()) :: [Message.t()]
  def next(%Topic{id: id}, %Message{} = message, n) do
    from(m in Message,
      where: m.topic_id == ^id and m.opened_at >= ^message.opened_at,
      where: m.opened_at > ^message.opened_at or m.id > ^message.id,
      order_by: [asc: m.opened_at, asc: m.id],
      limit: ^n
    )
    |> load()
  end

  @doc """
  `message` with `before` messages before it and `after` after it, in order: where a reader
  lands, from a permalink or their first unread message.
  """
  @spec around(Topic.t(), Message.t(), non_neg_integer(), non_neg_integer()) :: [Message.t()]
  def around(%Topic{} = topic, %Message{} = message, before, after_count) do
    before(topic, message, before) ++
      shown([message]) ++ next(topic, message, after_count)
  end

  @doc "From `message` to the end of its topic, in order."
  @spec since(Topic.t(), Message.t()) :: [Message.t()]
  def since(%Topic{} = topic, %Message{} = message),
    do: shown([message]) ++ next(topic, message, count(topic))

  @doc "Page `page` (from 1) of `size` messages, in order: `?page=n` without JavaScript."
  @spec page(Topic.t(), pos_integer(), pos_integer()) :: [Message.t()]
  def page(%Topic{id: id}, page, size) do
    from(m in Message,
      where: m.topic_id == ^id,
      order_by: [asc: m.opened_at, asc: m.id],
      offset: ^((page - 1) * size),
      limit: ^size
    )
    |> load()
  end

  @doc "How many messages come before `message` in its topic: its place, from 0."
  @spec position(Topic.t(), Message.t()) :: non_neg_integer()
  def position(%Topic{id: id}, %Message{} = message) do
    Repo.one(
      from m in Message,
        where: m.topic_id == ^id and m.opened_at <= ^message.opened_at,
        where: m.opened_at < ^message.opened_at or m.id < ^message.id,
        select: count()
    )
  end

  @doc "How many messages the topic holds, deleted ones too (their places stay, MO-02)."
  @spec count(Topic.t()) :: non_neg_integer()
  def count(%Topic{id: id}),
    do: Repo.one(from m in Message, where: m.topic_id == ^id, select: count())

  @doc "The page (from 1) of `size` messages that holds the message at `position`."
  @spec page_of(non_neg_integer(), pos_integer()) :: pos_integer()
  def page_of(position, size), do: div(position, size) + 1

  @doc "How many pages of `size` messages the topic fills: at least one."
  @spec pages(Topic.t(), pos_integer()) :: pos_integer()
  def pages(%Topic{} = topic, size), do: page_of(max(count(topic) - 1, 0), size)

  @doc "The id of the user's last message in the topic that is not deleted, or nil."
  @spec last_by(Topic.t(), User.t() | nil) :: Ecto.UUID.t() | nil
  def last_by(_topic, nil), do: nil

  def last_by(%Topic{id: id}, %User{id: user_id}) do
    Repo.one(
      from m in Message,
        where: m.topic_id == ^id and m.author_id == ^user_id and is_nil(m.deleted_at),
        order_by: [desc: m.opened_at, desc: m.id],
        limit: 1,
        select: m.id
    )
  end

  defp load(query), do: query |> Repo.all() |> shown()
  defp load_reversed(query), do: query |> Repo.all() |> Enum.reverse() |> shown()

  # What a topic view shows of each message, earlier versions rendered (GM-11).
  defp shown(messages),
    do: messages |> Repo.preload(@preload) |> Idejo.Messages.with_version_html()
end
