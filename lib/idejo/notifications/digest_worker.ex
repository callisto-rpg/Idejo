# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Notifications.DigestWorker do
  @moduledoc """
  Sends the email summaries that are due (`Idejo.Notifications.Digest.run/1`; steward
  decision, 2026-10-23), every hour (Oban cron, queue `maintenance`).
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias Idejo.Notifications.Digest

  @impl Oban.Worker
  def perform(_job) do
    Digest.run()
    :ok
  end
end
