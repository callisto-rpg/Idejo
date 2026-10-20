# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  # NO-01, NO-02, MVP §6: in-app notifications. At most one per user and message, so a
  # growing message notifies once (GM-13); kind is mention, reply or follow.
  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :read_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create unique_index(:notifications, [:user_id, :message_id])
    create index(:notifications, [:user_id, :updated_at])
    create constraint(:notifications, :kind, check: "kind IN ('mention', 'reply', 'follow')")
  end
end
