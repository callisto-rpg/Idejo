# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateReadPositions do
  use Ecto.Migration

  # TP-07, MVP §6: each user's read position per topic, the last message they have seen.
  # Messages opened after it are unread; a growing message keeps its opened_at, so it counts
  # once and does not turn unread again as it grows (GM-13).
  def change do
    create table(:read_positions, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :topic_id, references(:topics, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      # A deleted message (MO-02, M5) leaves the position at its time (updated_at).
      add :last_read_message_id,
          references(:messages, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, inserted_at: false)
    end

    create index(:read_positions, [:topic_id])
  end
end
