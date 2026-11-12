# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  # AP-08, AP-09 (steward decision, 2026-11-10): the official app's device tokens and the
  # one-minute codes that lead to them. Only SHA-256 hashes of either are stored.
  def change do
    create table(:api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 64, null: false
      add :scopes, {:array, :string}, null: false
      add :token_hash, :binary, null: false
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:user_id, :inserted_at])

    create table(:api_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :code_hash, :binary, null: false
      add :challenge, :string, null: false
      add :scopes, {:array, :string}, null: false
      add :device_name, :string, size: 64, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec
      add :token_id, references(:api_tokens, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:api_codes, [:code_hash])
    create index(:api_codes, [:user_id])
    create index(:api_codes, [:token_id])
  end
end
