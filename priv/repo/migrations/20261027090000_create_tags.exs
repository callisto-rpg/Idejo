# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateTags do
  use Ecto.Migration

  # TP-19 (steward decision, 2026-10-22): tags made by administrators, server-wide
  # (category_id NULL) or belonging to one category; a topic takes one or more. Names are
  # unique across the server, ignoring case, so a tag's slug names it in /tags links.
  # Deleting a category deletes its own tags, and so their place on topics.
  def up do
    create table(:tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :category_id, references(:categories, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:tags, ["lower(name)"], name: :tags_name_index)
    create unique_index(:tags, [:slug])
    create index(:tags, [:category_id])

    create table(:topic_tags, primary_key: false) do
      add :topic_id, references(:topics, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), primary_key: true
    end

    create index(:topic_tags, [:tag_id])

    # The "Edit tags" right (RP-04), allowed server-wide for the built-in moderator.
    drop constraint(:category_permissions, :right_is_known)

    create constraint(:category_permissions, :right_is_known,
             check: "\"right\" IN ('view', 'start', 'post', 'moderate', 'tag')"
           )

    execute """
    INSERT INTO category_permissions (id, role_id, "right", effect, inserted_at, updated_at)
    SELECT '#{Ecto.UUID.generate(version: 7)}', id, 'tag', 'allow', now(), now()
    FROM roles WHERE built_in AND name = 'moderator'
    """
  end

  def down do
    execute "DELETE FROM category_permissions WHERE \"right\" = 'tag'"
    drop constraint(:category_permissions, :right_is_known)

    create constraint(:category_permissions, :right_is_known,
             check: "\"right\" IN ('view', 'start', 'post', 'moderate')"
           )

    drop table(:topic_tags)
    drop table(:tags)
  end
end
