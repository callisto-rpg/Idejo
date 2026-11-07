# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateTopicalTopics do
  use Ecto.Migration

  # Topic Type (steward request, 2026-11-07): a category's topics are "user" (shown as their
  # starter's) or "topical": the opening message shows an icon from the set administrators
  # upload instead of its author, whose name never shows, and any moderator edits it.
  def change do
    create table(:topic_icons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :upload_id, references(:uploads, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    alter table(:categories) do
      add :topic_type, :string, null: false, default: "user"
    end

    create constraint(:categories, :topic_type_values, check: "topic_type IN ('user', 'topical')")

    alter table(:topics) do
      add :topical, :boolean, null: false, default: false
      add :icon_id, references(:topic_icons, type: :binary_id, on_delete: :nilify_all)
    end

    # A topic waiting for approval (MO-04) keeps the chosen icon.
    alter table(:pending_topics) do
      add :icon_id, references(:topic_icons, type: :binary_id, on_delete: :nilify_all)
    end

    # The opening message of a topical topic: shown without its author.
    alter table(:messages) do
      add :anonymous, :boolean, null: false, default: false
    end
  end
end
