# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreatePollsAndSpoilers do
  use Ecto.Migration

  # Steward decisions, 2026-10-23: `!poll` adds a poll under the author's message (one per
  # message, closing after a number of hours; anyone who may post votes, once or for several
  # answers), and `!spoiler` hides a message behind a Reveal button.
  def change do
    create table(:polls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :question, :text, null: false
      add :multiple, :boolean, null: false, default: false
      add :closes_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:polls, [:message_id])

    create table(:poll_options, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :text, :text, null: false
    end

    create index(:poll_options, [:poll_id])

    create table(:poll_votes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all), null: false

      add :option_id, references(:poll_options, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:poll_votes, [:option_id, :user_id])
    create index(:poll_votes, [:poll_id, :user_id])

    alter table(:messages) do
      add :spoiler, :boolean, null: false, default: false
    end
  end
end
