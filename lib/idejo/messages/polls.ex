# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Polls do
  @moduledoc """
  Polls (`!poll` in the composer; steward decision, 2026-10-23): a question with two to
  #{10} answers under one of the author's messages, one poll per message, taking one answer
  or several, and closing after a number of hours (decimals allowed, at most 168, as
  `!schedule`).

  Each answer may have an emoji and a bar colour (steward decision, 2026-11-02; none: the
  theme's primary colour), and a poll may hide its results until it closes.

  Anyone who may post in the topic votes (`Idejo.Forum.can_post?/2`), and may change their
  vote until the poll closes. Votes are anonymous: readers see counts only, and only once
  they voted or the poll closed (only once it closed with `hide_results`). Deleted messages
  take no votes.

  Each change reaches the topic's viewers as `{:poll, message_id, summary}`, worked out once
  (NF-01); `Idejo.Messages.PollWorker` sends it again when the poll closes.
  """
  import Ecto.Query

  alias Idejo.Accounts.User
  alias Idejo.Api.Changes
  alias Idejo.Emoji
  alias Idejo.Federation
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages
  alias Idejo.Messages.{Message, Poll, PollOption, PollVote, PollWorker, Scheduling}
  alias Idejo.RateLimit
  alias Idejo.Repo
  alias Idejo.Settings

  @max_options 10

  @typedoc "What a topic view shows of a poll; `votes` holds each voter's answers, never shown."
  @type summary :: %{
          id: Ecto.UUID.t(),
          question: String.t(),
          multiple: boolean(),
          hide_results: boolean(),
          closes_at: DateTime.t(),
          voters: non_neg_integer(),
          options: [
            %{
              id: Ecto.UUID.t(),
              text: String.t(),
              emoji: String.t() | nil,
              colour: String.t() | nil,
              count: non_neg_integer()
            }
          ],
          votes: %{Ecto.UUID.t() => [Ecto.UUID.t()]}
        }

  @typedoc "A poll checked by `validate/1`, ready to be added (`attach/3`)."
  @type valid :: %{
          question: String.t(),
          options: [%{text: String.t(), emoji: String.t() | nil, colour: String.t() | nil}],
          multiple: boolean(),
          hide_results: boolean(),
          seconds: pos_integer()
        }

  @doc "The most answers a poll takes."
  @spec max_options() :: pos_integer()
  def max_options, do: @max_options

  @doc """
  The bar colour of an answer without one: the theme's primary colour, as `#rrggbb` (the
  colour picker's own format).
  """
  @spec default_colour() :: String.t()
  def default_colour do
    case Settings.theme().primary do
      "#" <> hex when byte_size(hex) >= 6 -> "#" <> String.downcase(binary_part(hex, 0, 6))
      _ -> "#daa304"
    end
  end

  @doc """
  Adds a poll under the user's message. `attrs` as for `validate/1`.

  `message` may be its id, from a client: an unknown one is `:forbidden` too.

  Refused with `:forbidden` for someone else's or a deleted message, or without the post
  right; `:taken` when the message has a poll; `:question`, `:options` (fewer than two, or
  more than #{@max_options}) or `:hours` for what is missing or wrong.
  """
  @spec create(User.t(), Message.t() | Ecto.UUID.t(), map()) ::
          {:ok, summary()}
          | {:error, :forbidden | :taken | :question | :options | :hours | :rate_limited}
  def create(%User{} = user, message_id, attrs) when is_binary(message_id) do
    case Ecto.UUID.cast(message_id) do
      {:ok, id} ->
        case Repo.get(Message, id) do
          %Message{} = message -> create(user, message, attrs)
          nil -> {:error, :forbidden}
        end

      :error ->
        {:error, :forbidden}
    end
  end

  def create(%User{} = user, %Message{} = message, attrs) do
    with :ok <- may_add?(user, message),
         {:ok, valid} <- validate(attrs),
         :ok <- RateLimit.check(:vote, user.id),
         {:ok, summary} <- Repo.transact(fn -> attach(user, message, valid) end) do
      announce(message, summary)
      {:ok, summary}
    end
  end

  @doc """
  A poll without a message of its own (steward decision, 2026-10-24): posts a closed message
  whose text is the question (so excerpts, search and notifications read it), then adds the
  poll under it. `attrs` as for `create/3`; checked before anything is posted. `reply_to_id`
  as for `Idejo.Forum.post_message/3`.
  """
  @spec post(User.t(), Topic.t(), map(), Ecto.UUID.t() | nil) ::
          {:ok, Message.t(), summary()}
          | {:error,
             :forbidden | :question | :options | :hours | :rate_limited | Ecto.Changeset.t()}
  def post(%User{} = user, %Topic{} = topic, attrs, reply_to_id \\ nil) do
    with {:ok, %{question: question}} <- validate(attrs),
         {:ok, message} <-
           Forum.post_message(user, topic, %{"body" => question, "reply_to_id" => reply_to_id}),
         {:ok, summary} <- create(user, message, attrs) do
      {:ok, message, summary}
    end
  end

  @doc """
  Checks a poll's form. `attrs`: `"question"`; `"options"`, the answers (blank ones are left
  out), either texts with `"emojis"` and `"colours"` beside them in the same order, or maps
  with `"text"`, `"emoji"` and `"colour"`; `"multiple"` and `"hide_results"` (`"true"` or
  `true`); `"hours"` until it closes (`Idejo.Messages.Scheduling.parse_hours/1`). An
  unknown emoji or a colour that is not `#rrggbb` is dropped; the theme's colour
  (`default_colour/0`) is stored as none, so the bar follows the theme.

  `{:error, :question | :options | :hours}` for what is missing or wrong (fewer than two
  answers, or more than #{@max_options}).
  """
  @spec validate(map()) :: {:ok, valid()} | {:error, :question | :options | :hours}
  def validate(attrs) do
    question = String.trim(attrs["question"] || "")
    options = attrs |> options() |> Enum.reject(&(&1.text == ""))

    with :ok <- if(question == "", do: {:error, :question}, else: :ok),
         :ok <- if(length(options) in 2..@max_options//1, do: :ok, else: {:error, :options}),
         {:ok, seconds} <- hours(attrs["hours"]) do
      {:ok,
       %{
         question: question,
         options: options,
         multiple: attrs["multiple"] in [true, "true"],
         hide_results: attrs["hide_results"] in [true, "true"],
         seconds: seconds
       }}
    end
  end

  defp options(attrs) do
    emojis = List.wrap(attrs["emojis"])
    colours = List.wrap(attrs["colours"])
    default = default_colour()

    attrs["options"]
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.map(fn
      {%{} = option, _i} -> option(option["text"], option["emoji"], option["colour"], default)
      {text, i} -> option(text, Enum.at(emojis, i), Enum.at(colours, i), default)
    end)
  end

  defp option(text, emoji, colour, default) do
    colour = if is_binary(colour), do: String.downcase(String.trim(colour))

    %{
      text: if(is_binary(text), do: String.trim(text), else: ""),
      emoji: if(is_binary(emoji) and Emoji.lookup(emoji), do: emoji),
      colour:
        if(is_binary(colour) and colour =~ ~r/^#[0-9a-f]{6}$/ and colour != default, do: colour)
    }
  end

  @doc "True for a message posted by `post/4`: its text is only its poll's question."
  @spec poll_only?(Message.t(), summary() | nil) :: boolean()
  def poll_only?(_message, nil), do: false

  def poll_only?(%Message{body_md: body}, %{question: question}),
    do: String.trim(body || "") == question

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

  @doc """
  Adds a poll checked by `validate/1` under `message`, by `author` (its activity's actor),
  with no rights checked: `create/3` checks them, automessages (`Idejo.Messages.Automessages`)
  post as a server account. Call it inside a transaction, then `announce/2` the summary once
  it is committed.
  """
  @spec attach(User.t(), Message.t(), valid()) :: {:ok, summary()} | {:error, :taken | term()}
  def attach(%User{} = author, %Message{} = message, valid) do
    closes_at = DateTime.add(DateTime.utc_now(), valid.seconds, :second)
    poll_id = Federation.generate_id()

    with {:ok, _poll} <-
           %Poll{
             id: poll_id,
             message_id: message.id,
             question: valid.question,
             multiple: valid.multiple,
             hide_results: valid.hide_results,
             closes_at: closes_at
           }
           |> Ecto.Changeset.change()
           |> Ecto.Changeset.unique_constraint(:message_id)
           |> Repo.insert()
           |> taken(),
         {_count, _} <- Repo.insert_all(PollOption, option_rows(poll_id, valid.options)),
         {:ok, _job} <- Oban.insert(PollWorker.new(%{id: poll_id}, scheduled_at: closes_at)),
         {:ok, _activity} <- activity(author, message, valid.question),
         # AP-16: the message is in the app's catch-up with its poll.
         :ok <- Changes.touch(message.id) do
      {:ok, summary(message.id)}
    end
  end

  # Two polls for one message at once: the second finds the first's row.
  defp taken({:error, %Ecto.Changeset{}}), do: {:error, :taken}
  defp taken(result), do: result

  defp option_rows(poll_id, options) do
    options
    |> Enum.with_index()
    |> Enum.map(fn {option, position} ->
      %{
        id: Federation.generate_id(),
        poll_id: poll_id,
        position: position,
        text: option.text,
        emoji: option.emoji,
        colour: option.colour
      }
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
      announce(message, summary)
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
    # AP-16: the message is in the app's catch-up with its poll's new counts.
    :ok = Changes.touch(poll.message_id)
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

  @doc """
  The message holding the poll `poll_id`, when `user` may read it (a topic they may view, or
  a private conversation of theirs; `Forum.get_readable_message/2`), else nil. For a poll
  id from a client (the app votes by poll, AP-12).
  """
  @spec readable_message(User.t() | nil, term()) :: Message.t() | nil
  def readable_message(user, poll_id) when is_binary(poll_id) do
    with {:ok, id} <- Ecto.UUID.cast(poll_id),
         message_id when is_binary(message_id) <-
           Repo.one(from p in Poll, where: p.id == ^id, select: p.message_id) do
      Forum.get_readable_message(user, message_id)
    else
      _ -> nil
    end
  end

  def readable_message(_user, _poll_id), do: nil

  @doc "Whether a poll (or its summary) still takes votes."
  @spec open?(Poll.t() | summary(), DateTime.t()) :: boolean()
  def open?(%{closes_at: closes_at}, now \\ DateTime.utc_now()),
    do: DateTime.after?(closes_at, now)

  @doc """
  Whether `user` sees the counts: once they voted, and for everyone once it closed. The
  message's author sees them from the start. With `hide_results`, nobody sees them before
  it closes.
  """
  @spec results_shown?(summary(), User.t() | nil, Message.t(), DateTime.t()) :: boolean()
  def results_shown?(summary, user, message, now \\ DateTime.utc_now()) do
    not open?(summary, now) or
      (not Map.get(summary, :hide_results, false) and user != nil and
         (user.id == message.author_id or Map.has_key?(summary.votes, user.id)))
  end

  @doc "Called by `Idejo.Messages.PollWorker` when a poll closes: its topic hears of it."
  @spec closed(Ecto.UUID.t()) :: :ok
  def closed(poll_id) do
    case Repo.one(from p in Poll, where: p.id == ^poll_id, preload: :message) do
      nil -> :ok
      poll -> announce(poll.message, summary(poll.message_id))
    end
  end

  @doc "Sends a poll's summary to its topic's viewers, after the change is committed."
  @spec announce(Message.t(), summary()) :: :ok
  def announce(%Message{} = message, summary) do
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
      hide_results: poll.hide_results,
      closes_at: poll.closes_at,
      voters: map_size(by_user),
      options:
        for(
          option <- poll.options,
          do: %{
            id: option.id,
            text: option.text,
            emoji: option.emoji,
            colour: option.colour,
            count: Map.get(counts, option.id, 0)
          }
        ),
      votes: by_user
    }
  end
end
