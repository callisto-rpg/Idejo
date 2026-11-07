# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreatePendingTopics do
  use Ecto.Migration

  # MO-04: how each category takes new topics, and the topics waiting for a moderator's
  # approval. A waiting topic is kept apart from `topics` until approved, so no list, search,
  # notification or feed can show it.
  def change do
    alter table(:categories) do
      add :new_topics, :string, null: false, default: "open"
    end

    create constraint(:categories, :new_topics_mode,
             check: "new_topics IN ('open', 'approval', 'new_users', 'closed')"
           )

    create table(:pending_topics, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :category_id, references(:categories, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :tag_ids, {:array, :string}, null: false, default: []

      add :forked_from_message_id,
          references(:messages, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:pending_topics, [:category_id, :created_at])
    create index(:pending_topics, [:author_id])
  end
end
