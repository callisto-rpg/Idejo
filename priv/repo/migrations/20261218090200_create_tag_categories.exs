# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateTagCategories do
  use Ecto.Migration

  # A tag may belong to several categories (steward decision, 2026-11-14): server-wide when
  # it has none, as before. Names stay unique across the server, ignoring case.
  def up do
    create table(:tag_categories, primary_key: false) do
      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), primary_key: true

      add :category_id, references(:categories, type: :binary_id, on_delete: :delete_all),
        primary_key: true
    end

    create index(:tag_categories, [:category_id])

    execute """
    INSERT INTO tag_categories (tag_id, category_id)
    SELECT id, category_id FROM tags WHERE category_id IS NOT NULL
    """

    alter table(:tags) do
      remove :category_id
    end
  end

  def down do
    alter table(:tags) do
      add :category_id, references(:categories, type: :binary_id, on_delete: :delete_all)
    end

    # A tag of several categories keeps one of them.
    execute """
    UPDATE tags SET category_id = (
      SELECT min(category_id::text)::uuid FROM tag_categories WHERE tag_id = tags.id
    )
    """

    create index(:tags, [:category_id])
    drop table(:tag_categories)
  end
end
