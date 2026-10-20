# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateUploads do
  use Ecto.Migration

  # TP-12, MVP §6: uploaded images, stored on local disk; path is the file name in the
  # uploads directory, size in bytes after re-encoding.
  def change do
    create table(:uploads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :path, :string, null: false
      add :mime, :string, null: false
      add :size, :integer, null: false

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:uploads, [:user_id])
    create unique_index(:uploads, [:path])
  end
end
