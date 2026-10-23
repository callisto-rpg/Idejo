# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateEmailPreferences do
  use Ecto.Migration

  # Steward decision, 2026-10-23 (with NO-04): an email summary for members away for a day.
  # A user without a row has the defaults; `last_seen_at` tells how long they were away.
  def change do
    create table(:email_preferences, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :mentions, :boolean, null: false, default: true
      add :role_mentions, :boolean, null: false, default: false
      add :own_topics, :boolean, null: false, default: true
      add :followed_topics, :boolean, null: false, default: false
      add :new_topics, :boolean, null: false, default: false
      add :all_activity, :boolean, null: false, default: false
      add :once_a_week, :boolean, null: false, default: true
      add :digest_sent_at, :utc_datetime_usec
      add :unsubscribe_token, :string

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create unique_index(:email_preferences, [:unsubscribe_token])

    alter table(:users) do
      add :last_seen_at, :utc_datetime_usec
    end

    # Existing members count as seen now, so nobody gets a summary right after the update.
    execute "UPDATE users SET last_seen_at = now()", ""
  end
end
