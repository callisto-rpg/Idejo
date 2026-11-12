# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Reactions do
  @moduledoc """
  Reactions to messages (TP-17; steward decision, 2026-10-22).

  Any signed-in, verified reader who may view a topic reacts to its messages with emoji
  (`Idejo.Emoji`): `toggle/3` adds one, or takes it back when they had it. A user may add
  several emoji to one message. Messages deleted by a moderator (MO-02) and topics that are
  locked or archived (read only) take no reactions.

  Reactions store no notification: they show under the message (steward decision,
  2026-10-23, with the Notifications page gone), and the author gets a live bubble
  (`Idejo.Notifications.announce_reaction/3`). After each change the topic's viewers get
  `{:reactions, message_id, summary}`, worked out once (NF-01).
  """
  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Api.Changes
  alias Idejo.Emoji
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages
  alias Idejo.Messages.{Message, Reaction}
  alias Idejo.Notifications
  alias Idejo.RateLimit
  alias Idejo.Repo

  @typedoc "One emoji's reactions to a message, in the order they were first used."
  @type summary :: [%{emoji: String.t(), count: pos_integer(), user_ids: [Ecto.UUID.t()]}]

  @doc """
  Adds the user's reaction `emoji` (a name) to the message, or takes it back when they had it.
  Returns the message's new summary.
  """
  @spec toggle(User.t(), Message.t(), String.t()) ::
          {:ok, summary()} | {:error, :forbidden | :unknown_emoji | :rate_limited}
  def toggle(%User{} = user, %Message{} = message, emoji) when is_binary(emoji) do
    cond do
      not may_react?(user, message) -> {:error, :forbidden}
      Emoji.lookup(emoji) == nil -> {:error, :unknown_emoji}
      RateLimit.check(:react, user.id) != :ok -> {:error, :rate_limited}
      true -> save(user, message, Emoji.lookup(emoji).name)
    end
  end

  defp save(user, message, emoji) do
    {:ok, {summary, added?}} =
      Repo.transact(fn ->
        existing = Repo.get_by(Reaction, message_id: message.id, user_id: user.id, emoji: emoji)

        if existing do
          Repo.delete!(existing)
        else
          Repo.insert!(%Reaction{message_id: message.id, user_id: user.id, emoji: emoji},
            on_conflict: :nothing
          )
        end

        # AP-16: the message is in the app's catch-up with its new reactions.
        :ok = Changes.touch(message.id)
        {:ok, {summary(message.id), is_nil(existing)}}
      end)

    Messages.broadcast(message.topic_id, {:reactions, message.id, summary})
    # A bubble for the author, live only (steward decision, 2026-10-23).
    if added?, do: Notifications.announce_reaction(user, message, Emoji.lookup(emoji))
    {:ok, summary}
  end

  @doc """
  Sets whether `user` reacted to `message` with `emoji` (a name, `:name:` or the character):
  adds it when `wanted?` and it is not theirs yet, takes it back when not `wanted?` and it
  is; otherwise changes nothing (the app's PUT and DELETE, AP-12). Refused as `toggle/3`.
  """
  @spec set(User.t(), Message.t(), String.t(), boolean()) ::
          {:ok, summary()} | {:error, :forbidden | :unknown_emoji | :rate_limited}
  def set(%User{} = user, %Message{} = message, emoji, wanted?) when is_binary(emoji) do
    name =
      emoji
      |> String.trim(":")
      |> then(&(Emoji.lookup(&1) || Emoji.by_char(&1) || %{name: &1}).name)

    mine? = Enum.any?(summary(message.id), &(&1.emoji == name and user.id in &1.user_ids))

    cond do
      mine? != wanted? -> toggle(user, message, name)
      may_react?(user, message) -> {:ok, summary(message.id)}
      true -> {:error, :forbidden}
    end
  end

  @doc """
  Returns true when the user may react to the message: signed in and verified, the message
  not deleted, and its topic one they may view (or a private conversation they are in)
  that is neither locked nor archived.
  """
  @spec may_react?(User.t() | nil, Message.t()) :: boolean()
  def may_react?(nil, _message), do: false

  def may_react?(%User{} = user, %Message{} = message) do
    is_nil(message.deleted_at) and
      case Forum.get_readable_topic(user, message.topic_id) do
        %Topic{} = topic -> may_react_in?(user, topic)
        nil -> false
      end
  end

  @doc """
  Whether `user` may react in `topic`, one they may read: signed in and verified, and the
  topic neither locked nor archived. What a topic view asks once (no query per message);
  `may_react?/2` and `toggle/3` ask it too, with the message.
  """
  @spec may_react_in?(User.t() | nil, Topic.t()) :: boolean()
  def may_react_in?(nil, _topic), do: false

  def may_react_in?(%User{} = user, %Topic{state: state}),
    do: Accounts.confirmed?(user) and state == "open"

  @doc "The summaries of the given messages' reactions, as `%{message_id => summary}`."
  @spec summaries([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => summary()}
  def summaries([]), do: %{}

  def summaries(message_ids) do
    from(r in Reaction,
      where: r.message_id in ^message_ids,
      order_by: [asc: r.created_at, asc: r.id],
      select: {r.message_id, r.emoji, r.user_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_, emoji, user_id} -> {emoji, user_id} end)
    |> Map.new(fn {message_id, rows} -> {message_id, summarise(rows)} end)
  end

  @doc """
  Who reacted to the message, and with what (steward decision, 2026-10-28): each user once,
  in the order of their first reaction, with their emoji names in the order they chose them.
  Asked only when a reader opens the list, so the summaries stay free of names (NF-01).
  """
  @spec reactors(Ecto.UUID.t()) :: [%{user: User.t(), emoji: [String.t()]}]
  def reactors(message_id) when is_binary(message_id) do
    from(r in Reaction,
      join: u in assoc(r, :user),
      where: r.message_id == ^message_id,
      order_by: [asc: r.created_at, asc: r.id],
      select: {u, r.emoji}
    )
    |> Repo.all()
    |> Enum.reduce({[], %{}}, fn {user, emoji}, {order, emoji_by} ->
      order = if Map.has_key?(emoji_by, user.id), do: order, else: [user | order]
      {order, Map.update(emoji_by, user.id, [emoji], &(&1 ++ [emoji]))}
    end)
    |> then(fn {order, emoji_by} ->
      for user <- Enum.reverse(order), do: %{user: user, emoji: emoji_by[user.id]}
    end)
  end

  @doc """
  `reactors/1` for `viewer`, with a message id from a client: nothing unless they may read
  the message (`Idejo.Forum.get_readable_message/2`, private conversations of theirs too).
  """
  @spec reactors(User.t() | nil, term()) :: [%{user: User.t(), emoji: [String.t()]}]
  def reactors(viewer, message_id) when is_binary(message_id) do
    case Forum.get_readable_message(viewer, message_id) do
      %Message{id: id} -> reactors(id)
      nil -> []
    end
  end

  def reactors(_viewer, _message_id), do: []

  @doc "The summary of one message's reactions."
  @spec summary(Ecto.UUID.t()) :: summary()
  def summary(message_id), do: Map.get(summaries([message_id]), message_id, [])

  # Each emoji once, where it was first used, with everyone who used it.
  defp summarise(rows) do
    rows
    |> Enum.reduce({[], %{}}, fn {emoji, user_id}, {order, users} ->
      order = if Map.has_key?(users, emoji), do: order, else: [emoji | order]
      {order, Map.update(users, emoji, [user_id], &(&1 ++ [user_id]))}
    end)
    |> then(fn {order, users} ->
      for emoji <- Enum.reverse(order),
          do: %{emoji: emoji, count: length(users[emoji]), user_ids: users[emoji]}
    end)
  end
end
