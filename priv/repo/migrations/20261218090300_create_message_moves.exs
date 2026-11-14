# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateMessageMoves do
  use Ecto.Migration

  # TP-15: where moved messages were (steward request, 2026-11-14): a banner under the
  # message before the oldest of them, linking to the topic they went to.
  def change do
    create table(:message_moves, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_topic_id, references(:topics, type: :binary_id, on_delete: :delete_all),
        null: false

      add :after_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_topic_id, references(:topics, type: :binary_id, on_delete: :delete_all),
        null: false

      add :count, :integer, null: false
      add :new_topic, :boolean, null: false, default: false
      add :moved_at, :utc_datetime_usec, null: false
    end

    create index(:message_moves, [:after_message_id])
    create index(:message_moves, [:target_topic_id])
  end
end
