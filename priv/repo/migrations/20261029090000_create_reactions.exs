# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateReactions do
  use Ecto.Migration

  # TP-17 (steward decision, 2026-10-22): reactions on messages. One row per message, user
  # and emoji (its name: "joy", or a server reaction such as "agree"); a user may add several
  # emoji to one message. The author gets one notification per message, of kind "reaction".
  def up do
    create table(:reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:reactions, [:message_id, :user_id, :emoji])
    create index(:reactions, [:user_id])

    drop constraint(:notifications, :kind)

    create constraint(:notifications, :kind,
             check: "kind IN ('mention', 'reply', 'follow', 'reaction')"
           )
  end

  def down do
    execute "DELETE FROM notifications WHERE kind = 'reaction'"
    drop constraint(:notifications, :kind)
    create constraint(:notifications, :kind, check: "kind IN ('mention', 'reply', 'follow')")
    drop table(:reactions)
  end
end
