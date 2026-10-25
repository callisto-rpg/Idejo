# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Worker do
  @moduledoc """
  Sends one push to one browser (PN-13, PN-15), in the `push` queue. Args:
  `"subscription_id"`, `"payload"` (the declarative JSON, PN-12), `"ttl"` and `"urgency"`.

  What the push service answers:

    * 2xx: sent; `last_success_at` set, `failure_count` back to 0;
    * 404 or 410: the browser unsubscribed; the subscription is deleted;
    * 429 or 5xx, or no answer: a failure, tried again later, after `Retry-After` when the
      service gives one, else after a delay that doubles with each attempt;
    * any other status: a failure, not tried again (the request itself is wrong).

  After 5 failures in a row the subscription is deleted. Nothing is sent while push is off
  (PN-19), to a subscription deleted meanwhile, or to an endpoint that no longer passes
  `Idejo.Push.Endpoint` (PN-16).

  Changes to this module get an extra careful human review (DV-06).
  """
  use Oban.Worker, queue: :push, max_attempts: 10

  import Ecto.Query

  alias Idejo.Push
  alias Idejo.Push.{Sender, Subscription}
  alias Idejo.Repo

  @max_failures 5

  @doc "Failures in a row after which a subscription is deleted (PN-13)."
  @spec max_failures() :: pos_integer()
  def max_failures, do: @max_failures

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscription_id" => id} = args, attempt: attempt}) do
    cond do
      not Push.enabled?() -> {:cancel, :disabled}
      subscription = Repo.get(Subscription, id) -> send_to(subscription, args, attempt)
      true -> {:cancel, :unsubscribed}
    end
  end

  defp send_to(subscription, args, attempt) do
    opts = [ttl: args["ttl"], urgency: args["urgency"], contact: Push.contact()]

    case Sender.deliver(subscription, args["payload"], opts) do
      {:ok, status, _retry_after} when status in 200..299 ->
        succeeded(subscription)

      {:ok, status, _retry_after} when status in [404, 410] ->
        Repo.delete_all(from s in Subscription, where: s.id == ^subscription.id)
        :ok

      {:ok, status, retry_after} when status == 429 or status >= 500 ->
        failed(subscription, {:snooze, delay(attempt, retry_after)})

      {:ok, status, _retry_after} ->
        failed(subscription, {:cancel, {:status, status}})

      {:error, {:transport, _exception}} ->
        failed(subscription, {:snooze, delay(attempt, nil)})

      {:error, reason} ->
        {:cancel, reason}
    end
  end

  defp succeeded(subscription) do
    Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id),
      set: [last_success_at: DateTime.utc_now(), failure_count: 0]
    )

    :ok
  end

  defp failed(subscription, outcome) do
    {_, counts} =
      Repo.update_all(
        from(s in Subscription, where: s.id == ^subscription.id, select: s.failure_count),
        inc: [failure_count: 1]
      )

    if Enum.any?(counts, &(&1 >= @max_failures)) do
      Repo.delete_all(from s in Subscription, where: s.id == ^subscription.id)
      {:cancel, :too_many_failures}
    else
      outcome
    end
  end

  @doc """
  Seconds before trying again: the push service's `Retry-After` when longer, else 30 s
  doubled with each attempt, at most an hour.
  """
  @spec delay(pos_integer(), non_neg_integer() | nil) :: pos_integer()
  def delay(attempt, retry_after) do
    backoff = min(30 * Integer.pow(2, attempt - 1), 3600)
    max(backoff, retry_after || 0)
  end
end
