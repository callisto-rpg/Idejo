# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddForkedFromToTopics do
  use Ecto.Migration

  # TP-09, MVP §6: a topic started from a message ("New topic from this") links back to it.
  def change do
    alter table(:topics) do
      add :forked_from_message_id,
          references(:messages, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:topics, [:forked_from_message_id])
  end
end
