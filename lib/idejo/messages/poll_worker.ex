# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.PollWorker do
  @moduledoc """
  Tells a poll's topic that it closed, at its time (`Idejo.Messages.Polls.closed/1`; steward
  decision, 2026-10-23), so open views show its results. Queue `messages`.
  """
  use Oban.Worker, queue: :messages, max_attempts: 5

  alias Idejo.Messages.Polls

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}), do: Polls.closed(id)
end
