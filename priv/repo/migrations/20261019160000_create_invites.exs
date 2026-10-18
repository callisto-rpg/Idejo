# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateInvites do
  use Ecto.Migration

  # AC-02, MVP §6: code, created_by, used_by, expires_at. An invite is single-use; used_at
  # records when. Users are never hard-deleted (AC-07), so the references restrict.
  def change do
    create table(:invites, primary_key: false) do
      add :code, :string, primary_key: true
      add :created_by, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :used_by, references(:users, type: :binary_id, on_delete: :restrict)
      add :used_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:invites, [:created_at])
    create unique_index(:invites, [:used_by])
  end
end
