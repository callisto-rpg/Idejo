# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddSearch do
  use Ecto.Migration

  # SE-01 to SE-03, MVP §6: PostgreSQL full-text search with the 'simple' configuration
  # (steward decision: any language, no stemming). Each message is one document; its vector
  # is a generated column, so every commit re-indexes it (SE-03). Topic titles are searched
  # through an index on the same expression. `<` and `>` count as spaces: PostgreSQL's parser
  # would otherwise read them as HTML tags and drop the words inside <script> or <style>.
  def up do
    execute """
    ALTER TABLE messages ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        to_tsvector('simple'::regconfig, translate(coalesce(body_md, ''), '<>', '  '))
      ) STORED
    """

    create index(:messages, [:search_vector], using: :gin)

    execute """
    CREATE INDEX topics_title_search_index ON topics
      USING gin (to_tsvector('simple'::regconfig, title))
    """
  end

  def down do
    execute "DROP INDEX topics_title_search_index"
    drop index(:messages, [:search_vector])
    alter table(:messages), do: remove(:search_vector)
  end
end
