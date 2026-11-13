# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddUsernameChanges do
  use Ecto.Migration

  # AC-04, changing one's username (steward request, 2026-11-13): when it last changed (once
  # every 30 days), and the names given up, kept 30 days for whoever gave them up.
  def change do
    alter table(:users) do
      add :username_changed_at, :utc_datetime
    end

    create table(:released_usernames, primary_key: false) do
      add :username, :citext, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :released_at, :utc_datetime, null: false
    end

    create index(:released_usernames, [:user_id])
  end
end
