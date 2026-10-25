# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.FollowedWorker do
  @moduledoc """
  Followed activity (PN-04), in the `push` queue: "There are new messages in {N} topics you
  follow", opening the Unread page. Args: `"user_id"`. `Idejo.Push.dispatch/1` queues it
  when a message notifies a follower, at most one waiting per user, due when the last one
  went `push_followed_interval_minutes` ago.

  N counts the user's followed topics with unread messages they were notified of as a
  follower (`Idejo.Reading.unread_followed/1`: not mentions or replies, which have pushes
  of their own, PN-05; viewable; not muted), leaving out topics they have on screen
  (PN-08). It is sent only when one of those has activity since the last such push (N has
  grown), and only to an active, unbanned user who kept the type on (PN-11) while push is
  on (PN-19). The time and N of the push are kept in `push_preferences`.

  Changes to this module get an extra careful human review (DV-06).
  """
  use Oban.Worker,
    queue: :push,
    max_attempts: 3,
    unique: [keys: [:user_id], states: [:available, :scheduled, :retryable]]

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Messages.Authors
  alias Idejo.Push
  alias Idejo.Push.{Payload, Preference}
  alias Idejo.Reading
  alias Idejo.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    now = DateTime.utc_now()

    with :ok <- check(Push.enabled?(), :disabled),
         {:ok, user} <- user(user_id),
         preference = Push.preferences(user),
         :ok <- check(Push.wants?(preference, "follow"), :switched_off),
         :ok <- due(preference, now) do
      topics = followed_topics(user)

      if Enum.any?(topics, &new?(&1, preference)),
        do: send_push(user, preference, length(topics), now),
        else: :ok
    else
      {:snooze, seconds} -> {:snooze, seconds}
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp user(user_id) do
    case Repo.get(User, user_id) do
      %User{status: "active"} = user ->
        if Accounts.banned?(user), do: {:error, :banned}, else: {:ok, user}

      _ ->
        {:error, :no_account}
    end
  end

  # A job queued before the last push went waits for the interval's end.
  defp due(preference, now) do
    due = Push.followed_due(preference.followed_sent_at, now)

    case DateTime.diff(due, now) do
      wait when wait > 0 -> {:snooze, wait}
      _ -> :ok
    end
  end

  # The unread followed topics, but those on screen.
  defp followed_topics(user) do
    user
    |> Reading.unread_followed()
    |> Enum.reject(fn {topic_id, _latest} -> Authors.present?(topic_id, user.id) end)
  end

  defp new?(_topic, %Preference{followed_sent_at: nil}), do: true

  defp new?({_topic_id, latest}, %Preference{followed_sent_at: sent}),
    do: DateTime.after?(latest, sent)

  defp send_push(user, preference, count, now) do
    {:ok, _} =
      preference
      |> Ecto.Changeset.change(followed_sent_at: now, followed_count: count)
      |> Repo.insert_or_update()

    case Push.deliver(user, Payload.followed(user, count)) do
      {:ok, _queued} -> :ok
      {:error, reason} -> {:cancel, reason}
    end
  end
end
