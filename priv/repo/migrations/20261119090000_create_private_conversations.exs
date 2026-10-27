# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreatePrivateConversations do
  use Ecto.Migration

  # Private conversations (steward decision, 2026-10-27): topics outside every category, read
  # only by their participants. No category means every query that goes through one (lists,
  # search, the sitemap, unread) leaves them out.
  def up do
    alter table(:topics) do
      add :private, :boolean, null: false, default: false
    end

    execute "ALTER TABLE topics ALTER COLUMN category_id DROP NOT NULL"

    create constraint(:topics, :category_unless_private,
             check:
               "(private AND category_id IS NULL) OR (NOT private AND category_id IS NOT NULL)"
           )

    create table(:conversation_participants, primary_key: false) do
      add :topic_id, references(:topics, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:conversation_participants, [:user_id])

    alter table(:users) do
      add :accepts_private_messages, :boolean, null: false, default: true
    end
  end

  def down do
    execute "DELETE FROM topics WHERE private"

    alter table(:users) do
      remove :accepts_private_messages
    end

    drop table(:conversation_participants)
    drop constraint(:topics, :category_unless_private)
    execute "ALTER TABLE topics ALTER COLUMN category_id SET NOT NULL"

    alter table(:topics) do
      remove :private
    end
  end
end
