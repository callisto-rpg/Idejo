# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreatePushSubscriptions do
  use Ecto.Migration

  # PN-13: one row per browser that takes web push for a user. `session_id` is the sign-in's
  # socket id (`user_tokens.socket_id`), so the row goes when that session ends.
  def change do
    create table(:push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false
      add :user_agent, :string
      add :session_id, :string
      add :last_success_at, :utc_datetime_usec
      add :failure_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create unique_index(:push_subscriptions, [:endpoint])
    create index(:push_subscriptions, [:user_id, :created_at])
    create index(:push_subscriptions, [:session_id])
  end
end
