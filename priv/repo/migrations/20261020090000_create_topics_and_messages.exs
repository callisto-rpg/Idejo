# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateTopicsAndMessages do
  use Ecto.Migration

  # TP-01, MVP §6. A topic lives in one category; a category with topics cannot be deleted
  # until they go elsewhere (RP-03). Messages keep the growing-message columns of MVP §6
  # (opened_at, closes_at, closed_at) from the start; in M2 every message is posted closed.
  # forked_from_message_id (TP-09), commits (GM) and search_vector (SE) come with their
  # milestones.
  def change do
    create table(:topics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :uri, :string, null: false

      add :category_id, references(:categories, type: :binary_id, on_delete: :restrict),
        null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :title, :string, null: false
      add :slug, :string, null: false
      add :state, :string, null: false, default: "open"
      add :pinned, :boolean, null: false, default: false
      add :message_count, :integer, null: false, default: 0
      add :last_activity_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:topics, [:uri])
    create index(:topics, [:category_id, :pinned, :last_activity_at])
    create constraint(:topics, :state_valid, check: "state IN ('open', 'locked')")

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :uri, :string, null: false
      add :topic_id, references(:topics, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :reply_to_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :state, :string, null: false
      add :opened_at, :utc_datetime_usec, null: false
      add :closes_at, :utc_datetime_usec, null: false
      add :closed_at, :utc_datetime_usec
      add :body_md, :text, null: false
      add :body_html, :text, null: false
      add :edited, :boolean, null: false, default: false

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:messages, [:uri])
    # GM-08: messages read in the order they were opened.
    create index(:messages, [:topic_id, :opened_at])
    create constraint(:messages, :state_valid, check: "state IN ('open', 'closed')")
  end
end
