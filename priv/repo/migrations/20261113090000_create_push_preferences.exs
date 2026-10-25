# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreatePushPreferences do
  use Ecto.Migration

  # PN-11: each user's push types, all on by default (no row means the defaults). PN-05: a
  # notification is pushed at most once, `pushed_at` says when.
  def change do
    create table(:push_preferences, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :reply, :boolean, null: false, default: true
      add :mention, :boolean, null: false, default: true
      add :role_mention, :boolean, null: false, default: true
      add :followed, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    alter table(:notifications) do
      add :pushed_at, :utc_datetime_usec
    end
  end
end
