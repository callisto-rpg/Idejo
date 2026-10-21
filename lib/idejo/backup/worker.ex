# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Backup.Worker do
  @moduledoc """
  The nightly backup (AD-05): run by Oban's cron at 03:00 UTC, it makes a backup, then
  keeps the newest `Idejo.Backup.keep/0`. A failed backup is retried and deletes nothing.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3, unique: [period: 3600]

  require Logger

  alias Idejo.Backup

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Backup.create() do
      {:ok, _path} ->
        for name <- Backup.prune(), do: Logger.info("Old backup #{name} deleted")
        :ok

      {:error, reason} ->
        Logger.error("Backup failed: #{reason}")
        {:error, reason}
    end
  end

  # pg_dump of a large database, then copying the uploads, takes a while.
  @impl Oban.Worker
  def timeout(_job), do: :timer.hours(2)
end
