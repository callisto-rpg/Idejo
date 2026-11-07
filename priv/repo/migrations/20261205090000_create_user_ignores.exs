# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateUserIgnores do
  use Ecto.Migration

  # AC-06: who ignores whom. One row per pair; private to the one who ignores. Deleting an
  # account (AC-07) deletes its rows both ways; the cascade covers anything else.
  def change do
    create table(:user_ignores, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :ignored_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:user_ignores, [:ignored_id])
  end
end
