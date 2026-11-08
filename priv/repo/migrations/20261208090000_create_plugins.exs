# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreatePlugins do
  use Ecto.Migration

  # Plugins (steward request, 2026-11-08): composer commands defined by JSON files in the
  # plugins folder. A plugin's settings (on or off, the roles that may use it) live here, by
  # command, so deleting its file is all it takes to remove it; a row whose file is gone is
  # never shown, and keeps a bundled plugin from coming back.
  def change do
    create table(:plugin_settings, primary_key: false) do
      add :command, :string, primary_key: true
      add :enabled, :boolean, null: false, default: false
      add :role_ids, {:array, :binary_id}, null: false, default: []

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    # What a plugin added under a message: a video, a frame, a button or a card.
    create table(:message_embeds, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :plugin, :string, null: false
      add :block, :string, null: false
      add :data, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:message_embeds, [:message_id, :created_at])
  end
end
