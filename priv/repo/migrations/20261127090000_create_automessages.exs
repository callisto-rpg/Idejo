# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateAutomessages do
  use Ecto.Migration

  # Steward decisions, 2026-11-01: `!command`s that moderators (or, with `everyone`, anyone
  # who may post) use to have the server post a message written in Admin → Automessages,
  # sent by a server account (`users.status` "system") with its own username and picture.
  # `cooldown_minutes` holds the command back in a topic after it was posted there.
  def change do
    create table(:automessages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command, :citext, null: false
      add :body_md, :text, null: false
      add :sender_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :everyone, :boolean, null: false, default: false
      add :cooldown_minutes, :integer, null: false, default: 0

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:automessages, [:command])
    create index(:automessages, [:sender_id])

    # The automessage a message was posted from, for its cooldown.
    alter table(:messages) do
      add :automessage_id, references(:automessages, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:messages, [:automessage_id, :topic_id, :opened_at],
             where: "automessage_id IS NOT NULL"
           )
  end
end
