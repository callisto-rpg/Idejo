# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateScheduledMessages do
  use Ecto.Migration

  # Steward decision, 2026-10-23: `!schedule` in the composer posts a message later (at most
  # 168 hours). Until then only its author sees it, and may cancel it; once posted it is an
  # ordinary closed message marked `scheduled`.
  def change do
    create table(:scheduled_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :topic_id, references(:topics, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :reply_to_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :body_md, :text, null: false
      add :post_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:scheduled_messages, [:author_id, :topic_id])

    alter table(:messages) do
      add :scheduled, :boolean, null: false, default: false
    end
  end
end
