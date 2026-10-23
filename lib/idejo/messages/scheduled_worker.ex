# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.ScheduledWorker do
  @moduledoc """
  Posts one scheduled message at its time (`Idejo.Messages.Scheduling.post/1`; steward
  decision, 2026-10-23). Queue `messages`.
  """
  use Oban.Worker, queue: :messages, max_attempts: 5

  alias Idejo.Messages.Scheduling

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}), do: Scheduling.post(id)
end
