# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    # AC-01, MVP §6. avatar_id arrives with uploads (AC-04, TP-12).
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :uri, :string, null: false
      add :email, :citext, null: false
      add :password_hash, :string, null: false
      add :username, :citext, null: false
      add :display_name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :origin, :string, null: false, default: "local"
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:users, [:uri])
    create unique_index(:users, [:email])
    create unique_index(:users, [:username])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    # FD-02 outbox for future federation.
    create table(:activities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_uri, :string, null: false
      add :verb, :string, null: false
      add :object_uri, :string, null: false
      add :target_uri, :string
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:activities, [:created_at])
    create index(:activities, [:object_uri])
  end
end
