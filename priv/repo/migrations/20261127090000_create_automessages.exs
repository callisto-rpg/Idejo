# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateAutomessages do
  use Ecto.Migration

  # Steward decision, 2026-11-01: `!command`s that moderators use to have the server post a
  # message written in Admin → Automessages, sent by a server account (`users.status`
  # "system") with its own username and picture.
  def change do
    create table(:automessages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command, :citext, null: false
      add :body_md, :text, null: false
      add :body_html, :text, null: false
      add :sender_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:automessages, [:command])
    create index(:automessages, [:sender_id])
  end
end
