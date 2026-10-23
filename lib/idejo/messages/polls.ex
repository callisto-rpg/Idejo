# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Polls do
  @moduledoc """
  Polls (`!poll` in the composer; steward decision, 2026-10-23): a question with two to
  #{10} answers under one of the author's messages, one poll per message, taking one answer
  or several, and closing after a number of hours (decimals allowed, at most 168, as
  `!schedule`).

  Anyone who may post in the topic votes (`Idejo.Forum.can_post?/2`), and may change their
  vote until the poll closes. Votes are anonymous: readers see counts only, and only once
  they voted or the poll closed. Deleted messages take no votes.

  Each change reaches the topic's viewers as `{:poll, message_id, summary}`, worked out once
  (NF-01); `Idejo.Messages.PollWorker` sends it again when the poll closes.
  """
  import Ecto.Query

  alias Idejo.Accounts.User
  alias Idejo.Federation
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages
  alias Idejo.Messages.{Message, Poll, PollOption, PollVote, PollWorker, Scheduling}
  alias Idejo.RateLimit
  alias Idejo.Repo

  @max_options 10

  @typedoc "What a topic view shows of a poll; `votes` holds each voter's answers, never shown."
  @type summary :: %{
          id: Ecto.UUID.t(),
          question: String.t(),
          multiple: boolean(),
          closes_at: DateTime.t(),
          voters: non_neg_integer(),
          options: [%{id: Ecto.UUID.t(), text: String.t(), count: non_neg_integer()}],
          votes: %{Ecto.UUID.t() => [Ecto.UUID.t()]}
        }

  @doc "The most answers a poll takes."
  @spec max_options() :: pos_integer()
  def max_options, do: @max_options

  @doc """
  Adds a poll under the user's message. `attrs`: `"question"`, `"options"` (a list of
  answers; blank ones are left out), `"multiple"` (`"true"` or `true` for several answers)
  and `"hours"` (until it closes, `Idejo.Messages.Scheduling.parse_hours/1`).

  Refused with `:forbidden` for someone else's or a deleted message, or without the post
  right; `:taken` when the message has a poll; `:question`, `:options` (fewer than two, or
  more than #{@max_options}) or `:hours` for what is missing or wrong.
  """
  @spec create(User.t(), Message.t(), map()) ::
          {:ok, summary()}
          | {:error, :forbidden | :taken | :question | :options | :hours | :rate_limited}
  def create(%User{} = user, %Message{} = message, attrs) do
    question = String.trim(attrs["question"] || "")

    options =
      for text <- List.wrap(attrs["options"]), text = String.trim(text), text != "", do: text

    with :ok <- may_add?(user, message),
         :ok <- if(question == "", do: {:error, :question}, else: :ok),
         :ok <- if(length(options) in 2..@max_options//1, do: :ok, else: {:error, :options}),
         {:ok, seconds} <- hours(attrs["hours"]),
         :ok <- RateLimit.check(:vote, user.id) do
      insert(user, message, question, options, attrs["multiple"] in [true, "true"], seconds)
    end
  end

  defp may_add?(user, message) do
    topic = Repo.get!(Topic, message.topic_id)

    cond do
      message.author_id != user.id -> {:error, :forbidden}
      message.deleted_at != nil -> {:error, :forbidden}
      not Forum.can_post?(user, topic) -> {:error, :forbidden}
      Repo.exists?(from p in Poll, where: p.message_id == ^message.id) -> {:error, :taken}
      true -> :ok
    end
  end

  defp hours(text) do
    case Scheduling.parse_hours(text || "") do
      {:ok, seconds} -> {:ok, seconds}
      :error -> {:error, :hours}
    end
  end

  defp insert(user, message, question, options, multiple?, seconds) do
    closes_at = DateTime.add(DateTime.utc_now(), seconds, :second)
    poll_id = Federation.generate_id()

    result =
      Repo.transact(fn ->
        with {:ok, _poll} <-
               %Poll{
                 id: poll_id,
                 message_id: message.id,
                 question: question,
                 multiple: multiple?,
                 closes_at: closes_at
               }
               |> Ecto.Changeset.change()
               |> Ecto.Changeset.unique_constraint(:message_id)
               |> Repo.insert()
               |> taken(),
             {_count, _} <- Repo.insert_all(PollOption, option_rows(poll_id, options)),
             {:ok, _job} <- Oban.insert(PollWorker.new(%{id: poll_id}, scheduled_at: closes_at)),
             {:ok, _activity} <- activity(user, message, question) do
          {:ok, summary(message.id)}
        end
      end)

    with {:ok, summary} <- result, do: broadcast(message, summary)
    result
  end

  # Two polls for one message at once: the second finds the first's row.
  defp taken({:error, %Ecto.Changeset{}}), do: {:error, :taken}
  defp taken(result), do: result

  defp option_rows(poll_id, options) do
    options
    |> Enum.with_index()
    |> Enum.map(fn {text, position} ->
      %{id: Federation.generate_id(), poll_id: poll_id, position: position, text: text}
    end)
  end

  # FD-02: the message gained a poll.
  defp activity(user, message, question) do
    topic_uri = Repo.one!(from t in Topic, where: t.id == ^message.topic_id, select: t.uri)

    Repo.insert(
      Federation.activity_changeset(%{
        actor_uri: user.uri,
        verb: "update",
        object_uri: message.uri,
        target_uri: topic_uri,
        payload: %{"type" => "Note", "poll" => question}
      })
    )
  end

  @doc """
  Records the user's vote: `option_ids` are their answers (exactly one unless the poll takes
  several; none takes the vote back), replacing any earlier vote. Returns the new summary.
  """
  @spec vote(User.t(), Message.t(), [String.t()]) ::
          {:ok, summary()} | {:error, :forbidden | :closed | :invalid | :rate_limited}
  def vote(%User{} = user, %Message{} = message, option_ids) when is_list(option_ids) do
    poll = Repo.one(from p in Poll, where: p.message_id == ^message.id, preload: :options)

    with %Poll{} <- poll || {:error, :forbidden},
         :ok <- may_vote?(user, message),
         :ok <- if(open?(poll), do: :ok, else: {:error, :closed}),
         {:ok, chosen} <- chosen(poll, option_ids),
         :ok <- RateLimit.check(:vote, user.id) do
      {:ok, summary} = Repo.transact(fn -> replace_votes(poll, user, chosen) end)
      broadcast(message, summary)
      {:ok, summary}
    end
  end

  defp replace_votes(poll, user, chosen) do
    Repo.delete_all(from v in PollVote, where: v.poll_id == ^poll.id and v.user_id == ^user.id)
    now = DateTime.utc_now()

    rows =
      for id <- chosen,
          do: %{
            id: Federation.generate_id(),
            poll_id: poll.id,
            option_id: id,
            user_id: user.id,
            created_at: now
          }

    Repo.insert_all(PollVote, rows)
    {:ok, summary(poll.message_id)}
  end

  defp may_vote?(user, message) do
    topic = Repo.get!(Topic, message.topic_id)

    if message.deleted_at == nil and Forum.can_post?(user, topic),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp chosen(poll, option_ids) do
    known = MapSet.new(poll.options, & &1.id)
    chosen = Enum.uniq(option_ids)

    cond do
      not Enum.all?(chosen, &MapSet.member?(known, &1)) -> {:error, :invalid}
      not poll.multiple and length(chosen) > 1 -> {:error, :invalid}
      true -> {:ok, chosen}
    end
  end

  @doc "Whether a poll (or its summary) still takes votes."
  @spec open?(Poll.t() | summary(), DateTime.t()) :: boolean()
  def open?(%{closes_at: closes_at}, now \\ DateTime.utc_now()),
    do: DateTime.after?(closes_at, now)

  @doc """
  Whether `user` sees the counts: once they voted, and for everyone once it closed. The
  message's author sees them from the start.
  """
  @spec results_shown?(summary(), User.t() | nil, Message.t(), DateTime.t()) :: boolean()
  def results_shown?(summary, user, message, now \\ DateTime.utc_now()) do
    not open?(summary, now) or
      (user != nil and (user.id == message.author_id or Map.has_key?(summary.votes, user.id)))
  end

  @doc "Called by `Idejo.Messages.PollWorker` when a poll closes: its topic hears of it."
  @spec closed(Ecto.UUID.t()) :: :ok
  def closed(poll_id) do
    case Repo.one(from p in Poll, where: p.id == ^poll_id, preload: :message) do
      nil -> :ok
      poll -> broadcast(poll.message, summary(poll.message_id))
    end
  end

  defp broadcast(message, summary) do
    Messages.broadcast(message.topic_id, {:poll, message.id, summary})
    :ok
  end

  @doc "The polls of the given messages, as `%{message_id => summary}`; messages without one are left out."
  @spec summaries([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => summary()}
  def summaries([]), do: %{}

  def summaries(message_ids) do
    polls =
      Repo.all(from p in Poll, where: p.message_id in ^message_ids, preload: :options)

    votes =
      from(v in PollVote,
        where: v.poll_id in ^Enum.map(polls, & &1.id),
        select: {v.poll_id, v.user_id, v.option_id}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))

    Map.new(polls, fn poll -> {poll.message_id, summarise(poll, Map.get(votes, poll.id, []))} end)
  end

  @doc "The summary of one message's poll, or `nil`."
  @spec summary(Ecto.UUID.t()) :: summary() | nil
  def summary(message_id), do: Map.get(summaries([message_id]), message_id)

  defp summarise(poll, rows) do
    by_user = Enum.group_by(rows, &elem(&1, 0), &elem(&1, 1))
    counts = Enum.frequencies_by(rows, &elem(&1, 1))

    %{
      id: poll.id,
      question: poll.question,
      multiple: poll.multiple,
      closes_at: poll.closes_at,
      voters: map_size(by_user),
      options:
        for(
          option <- poll.options,
          do: %{id: option.id, text: option.text, count: Map.get(counts, option.id, 0)}
        ),
      votes: by_user
    }
  end
end
