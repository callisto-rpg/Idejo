# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Uploads.CleanupWorker do
  @moduledoc """
  The nightly clean-up of uploads (TP-12): run by Oban's cron at 04:00 UTC, after the
  backup, it deletes the uploads nothing uses (`Idejo.Uploads.delete_unused/1`).
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3, unique: [period: 3600]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Idejo.Uploads.delete_unused() do
      [] -> :ok
      names -> Logger.info("#{length(names)} unused uploads deleted")
    end

    :ok
  end
end
