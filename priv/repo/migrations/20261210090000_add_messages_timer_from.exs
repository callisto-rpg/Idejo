# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMessagesTimerFrom do
  use Ecto.Migration

  # The patience timers start when the author starts typing (steward request, 2026-11-09):
  # when that was, on the server's clock, for the window (closes_at) and the unanswered
  # message time. Nil for messages opened before, which count from opened_at.
  def change do
    alter table(:messages) do
      add :timer_from, :utc_datetime_usec
    end
  end
end
