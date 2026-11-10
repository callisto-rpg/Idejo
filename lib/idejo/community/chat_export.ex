# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Community.ChatExport do
  @moduledoc """
  What the chat service (`Idejo.Community.Chat`; steward request, 2026-11-10) reads about one
  member, after a ticket named them:

    * `followed_topics/1`: the topics they follow, as their sidebar has them (view right in
      the query), the most recently active first, with what the expanded topic list shows of
      each (`Idejo.Forum.topic_previews/1`) and their unread count;
    * `conversations/1`: their private conversations still here whose every participant is
      linked to the provider, with their messages (not deleted), so the service can copy
      them; `moved/2` then marks those it copied (`topics.moved_to_chat_at`), which the
      forum no longer lists or opens (`Idejo.Conversations`). Conversations with someone not
      linked stay here, counted in `remaining`.
  """

  import Ecto.Query

  alias Idejo.Accounts.{OIDC, User, UserIdentity}
  alias Idejo.Conversations.Participant
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages.{Message, Reaction}
  alias Idejo.{Reading, Repo}

  @topics 50

  @doc """
  The topics `user` follows, at most #{@topics}, the latest active first:
  `[%{topic:, unread:, preview:}]`, topics with their category.
  """
  @spec followed_topics(User.t()) :: [map()]
  def followed_topics(%User{} = user) do
    topics =
      user
      |> Reading.list_followed_topics()
      |> Enum.sort_by(& &1.last_activity_at, {:desc, DateTime})
      |> Enum.take(@topics)
      |> Repo.preload(:category)

    ids = Enum.map(topics, & &1.id)
    unread = Reading.unread_counts(user, ids)
    previews = Forum.topic_previews(ids)

    for topic <- topics,
        do: %{topic: topic, unread: Map.get(unread, topic.id, 0), preview: previews[topic.id]}
  end

  @doc """
  `user`'s private conversations still here with only linked participants, oldest first:
  `%{conversations: [%{topic:, subjects:, messages:}], remaining: n}`. Each message carries
  its author's subject (`author_subject`) and its reactions as `{emoji, subject}`; `remaining`
  counts the conversations left out (someone not linked).
  """
  @spec conversations(User.t()) :: %{conversations: [map()], remaining: non_neg_integer()}
  def conversations(%User{id: user_id}) do
    issuer = issuer()

    topics =
      Repo.all(
        from t in Topic,
          join: p in Participant,
          on: p.topic_id == t.id and p.user_id == ^user_id,
          where: t.private and is_nil(t.moved_to_chat_at),
          order_by: [asc: t.created_at, asc: t.id],
          preload: [:participants]
      )

    user_ids = topics |> Enum.flat_map(fn t -> Enum.map(t.participants, & &1.user_id) end)
    subjects = subjects(issuer, Enum.uniq(user_ids))

    {movable, kept} =
      Enum.split_with(topics, fn t ->
        Enum.all?(t.participants, &Map.has_key?(subjects, &1.user_id))
      end)

    messages = messages(Enum.map(movable, & &1.id), subjects)

    %{
      conversations:
        for topic <- movable do
          %{
            topic: topic,
            subjects: Enum.map(topic.participants, &subjects[&1.user_id]),
            messages: Map.get(messages, topic.id, [])
          }
        end,
      remaining: length(kept)
    }
  end

  @doc """
  Marks as copied those of `ids` that are `user`'s private conversations with only linked
  participants: `{:ok, count}`.
  """
  @spec moved(User.t(), [String.t()]) :: {:ok, non_neg_integer()}
  def moved(%User{} = user, ids) when is_list(ids) do
    movable = user |> conversations() |> Map.fetch!(:conversations) |> MapSet.new(& &1.topic.id)
    ids = for id <- ids, is_binary(id), MapSet.member?(movable, id), do: id

    {count, _} =
      Repo.update_all(from(t in Topic, where: t.id in ^ids),
        set: [moved_to_chat_at: DateTime.utc_now()]
      )

    {:ok, count}
  end

  defp issuer do
    case OIDC.config() do
      oidc when is_list(oidc) -> oidc[:issuer]
      _ -> nil
    end
  end

  defp subjects(nil, _user_ids), do: %{}

  defp subjects(issuer, user_ids) do
    Repo.all(
      from i in UserIdentity,
        join: u in User,
        on: u.id == i.user_id,
        where: i.issuer == ^issuer and i.user_id in ^user_ids and u.status == "active",
        select: {i.user_id, i.subject}
    )
    |> Map.new()
  end

  defp messages([], _subjects), do: %{}

  defp messages(topic_ids, subjects) do
    messages =
      Repo.all(
        from m in Message,
          where: m.topic_id in ^topic_ids and is_nil(m.deleted_at),
          order_by: [asc: m.opened_at, asc: m.id]
      )

    reactions =
      Repo.all(
        from r in Reaction,
          where: r.message_id in ^Enum.map(messages, & &1.id),
          select: {r.message_id, r.user_id, r.emoji}
      )
      |> Enum.group_by(&elem(&1, 0), fn {_, user_id, emoji} -> {emoji, subjects[user_id]} end)

    messages
    |> Enum.map(fn m ->
      %{
        message: m,
        author_subject: subjects[m.author_id],
        reactions:
          for({emoji, subject} <- Map.get(reactions, m.id, []), subject, do: {emoji, subject})
      }
    end)
    |> Enum.group_by(& &1.message.topic_id)
  end
end
