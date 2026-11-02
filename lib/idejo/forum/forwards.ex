# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.Forwards do
  @moduledoc """
  Forward (steward decision, 2026-11-02): a reader sends a message (someone else's, or their
  own once committed) to another topic, where it opens the composer as a new message
  carrying it (`messages.forwarded_from_id`, set by `Idejo.Messages.commit/4`).

  `targets/2` lists where it can go: open topics in categories where the user may view and
  post, and their own private conversations, the ones they read last first, or those
  matching a search. `readable_ids/2` says which forwarded messages a reader may see: those
  of a topic they may view, or of a private conversation of theirs. A reader who may not
  still sees the forwarded text when the forwarder wrote it (they shared their own words),
  only without the topic's name.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Conversations.Participant
  alias Idejo.Forum
  alias Idejo.Forum.{Category, Topic}
  alias Idejo.Messages.Message
  alias Idejo.Reading.ReadPosition
  alias Idejo.Repo

  @limit 10

  @typedoc "A place to forward to, as the forward card lists it."
  @type target :: %{
          id: Ecto.UUID.t(),
          title: String.t(),
          path: String.t(),
          place: String.t() | :private
        }

  @doc """
  Whether `user` may forward `message`: signed in, the message not deleted, and either
  someone else's or their own once closed (an open one is still being written).
  """
  @spec may_forward?(User.t() | nil, Message.t()) :: boolean()
  def may_forward?(nil, _message), do: false
  def may_forward?(_user, %Message{deleted_at: %DateTime{}}), do: false
  def may_forward?(%User{id: id}, %Message{author_id: id, state: state}), do: state == "closed"
  def may_forward?(%User{}, %Message{}), do: true

  @doc """
  Where `user` may forward to: with an empty `query`, the topics and conversations they
  read last; else those whose title (a conversation: the other person's name or username)
  contains it. At most #{@limit}; `except` (the topic forwarded from) left out.
  """
  @spec targets(User.t(), String.t(), Ecto.UUID.t() | nil) :: [target()]
  def targets(%User{id: user_id} = user, query, except \\ nil) do
    postable =
      Category
      |> where([c], not c.archive)
      |> Access.where_allowed(user, [:view, :post])
      |> select([c], c.id)

    mine = from p in Participant, where: p.user_id == ^user_id, select: p.topic_id

    base =
      from t in Topic,
        as: :topic,
        left_join: r in ReadPosition,
        on: r.topic_id == t.id and r.user_id == ^user_id,
        where: t.state == "open",
        where: t.category_id in subquery(postable) or (t.private and t.id in subquery(mine)),
        limit: @limit,
        preload: [:category, participants: :user]

    base = if except, do: from(t in base, where: t.id != ^except), else: base

    query
    |> String.trim()
    |> search(base, user_id)
    |> Repo.all()
    |> Enum.map(&target(&1, user_id))
  end

  defp search("", base, _user_id) do
    from [t, r] in base, order_by: [desc_nulls_last: r.updated_at, desc: t.last_activity_at]
  end

  defp search(text, base, user_id) do
    like = "%" <> String.replace(String.downcase(text), ~w(\\ % _), &("\\" <> &1)) <> "%"

    named =
      from p in Participant,
        join: u in assoc(p, :user),
        where: p.topic_id == parent_as(:topic).id and p.user_id != ^user_id,
        where:
          like(fragment("lower(?)", u.display_name), ^like) or
            like(fragment("lower(?)", u.username), ^like),
        select: 1

    from t in base,
      where:
        (not t.private and like(fragment("lower(?)", t.title), ^like)) or
          (t.private and exists(named)),
      order_by: [desc: t.last_activity_at, desc: t.id]
  end

  defp target(%Topic{private: true} = topic, user_id) do
    names = for %{user: u} <- topic.participants, u.id != user_id, do: u.display_name
    %{id: topic.id, title: Enum.join(names, ", "), path: "/p/#{topic.id}", place: :private}
  end

  defp target(%Topic{} = topic, _user_id) do
    %{
      id: topic.id,
      title: topic.title,
      path: "/t/#{topic.id}/#{topic.slug}",
      place: topic.category.name
    }
  end

  @doc """
  Of the given messages (forwarded ones), the ids of those `user` may read: in a topic they
  may view, or in a private conversation of theirs. Filtered in the query.
  """
  @spec readable_ids(User.t() | nil, [Ecto.UUID.t()]) :: MapSet.t()
  def readable_ids(_user, []), do: MapSet.new()

  def readable_ids(nil, ids), do: Forum.viewable_message_ids(nil, ids)

  def readable_ids(%User{id: user_id} = user, ids) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)
    mine = from p in Participant, where: p.user_id == ^user_id, select: p.topic_id

    from(m in Message,
      join: t in Topic,
      on: t.id == m.topic_id,
      where: m.id in ^ids,
      where: t.category_id in subquery(viewable) or (t.private and t.id in subquery(mine)),
      select: m.id
    )
    |> Repo.all()
    |> MapSet.new()
  end
end
