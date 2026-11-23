# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddTopicIconEmoji do
  use Ecto.Migration

  # Topic Type (steward request, 2026-11-24): a topic's icon may be any Twemoji emoji. Each
  # emoji chosen is one row, made at its first use, drawn from its Twemoji image: no upload.
  def up do
    alter table(:topic_icons) do
      add :emoji, :string
    end

    execute "ALTER TABLE topic_icons ALTER COLUMN upload_id DROP NOT NULL"

    create unique_index(:topic_icons, [:emoji])

    create constraint(:topic_icons, :upload_or_emoji,
             check: "(upload_id IS NULL) <> (emoji IS NULL)"
           )
  end

  def down do
    execute "DELETE FROM topic_icons WHERE emoji IS NOT NULL"
    drop constraint(:topic_icons, :upload_or_emoji)
    drop index(:topic_icons, [:emoji])
    execute "ALTER TABLE topic_icons ALTER COLUMN upload_id SET NOT NULL"

    alter table(:topic_icons) do
      remove :emoji
    end
  end
end
