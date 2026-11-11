# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Api.Changes do
  @moduledoc """
  Catch-up after a disconnect (AP-16; steward decision, 2026-11-10). Every write to a
  message row takes the next value of the `message_change_seq` sequence (`messages.change_seq`,
  set by a database trigger), after a transaction lock on its topic, so within a topic the
  values follow the order the writes committed in: a client that saw cursor N and asks for
  what came after N misses nothing. A topic's cursor is its highest value.

  Reactions and votes change no column of their message, so they `touch/1` it: the message
  comes back in the catch-up with its new reactions or poll.

  Nothing is ever dropped (the values live on the rows), so a cursor only expires when it
  is ahead of the topic (a backup restored meanwhile): `{:error, :cursor_expired}`, and the
  client loads the topic again.
  """
  import Ecto.Query

  alias Idejo.Forum.Topic
  alias Idejo.Messages.Message
  alias Idejo.Repo

  @doc "The topic's current cursor: its latest change, or 0 before any."
  @spec cursor(Topic.t()) :: non_neg_integer()
  def cursor(%Topic{id: id}) do
    Repo.one(from m in Message, where: m.topic_id == ^id, select: max(m.change_seq)) || 0
  end

  @doc """
  The topic's messages changed after `since`, oldest change first, at most `limit`:
  `{:ok, messages, cursor, more?}` with the cursor to ask from next (the last change given,
  or `since` when there is none).
  """
  @spec since(Topic.t(), non_neg_integer(), pos_integer()) ::
          {:ok, [Message.t()], non_neg_integer(), boolean()} | {:error, :cursor_expired}
  def since(%Topic{id: id} = topic, since, limit) when is_integer(since) and since >= 0 do
    if since > cursor(topic) do
      {:error, :cursor_expired}
    else
      rows =
        Repo.all(
          from m in Message,
            where: m.topic_id == ^id and m.change_seq > ^since,
            order_by: [asc: m.change_seq],
            limit: ^(limit + 1)
        )

      taken = Enum.take(rows, limit)
      last = List.last(taken)
      {:ok, taken, (last && last.change_seq) || since, length(rows) > limit}
    end
  end

  @doc """
  Marks a message changed without changing it, inside the caller's transaction: its
  reactions or its poll did (the trigger gives it a new `change_seq`).
  """
  @spec touch(Ecto.UUID.t()) :: :ok
  def touch(message_id) do
    Repo.update_all(from(m in Message, where: m.id == ^message_id), set: [change_seq: 0])
    :ok
  end
end
