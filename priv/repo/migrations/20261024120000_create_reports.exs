# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateReports do
  use Ecto.Migration

  # MO-01, MVP §6: a member reports a message with a reason; moderators resolve or dismiss
  # it (the moderation log records how, MO-03). One open report per reporter and message.
  def change do
    create table(:reports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :reporter_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :reason, :text, null: false
      add :status, :string, null: false, default: "open"
      add :handled_by_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :handled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create constraint(:reports, :status, check: "status IN ('open', 'resolved', 'dismissed')")
    create index(:reports, [:status, :created_at])

    create unique_index(:reports, [:message_id, :reporter_id],
             where: "status = 'open'",
             name: :reports_one_open_per_reporter
           )
  end
end
