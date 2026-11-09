# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMessagesHeld do
  use Ecto.Migration

  # Ctrl+Enter while the patience timer runs (steward request, 2026-11-09): the message is
  # committed (closed) at once, and its author's next message in the topic waits until the
  # timer would have let it start. `held` marks a message closed that way.
  def change do
    alter table(:messages) do
      add :held, :boolean, null: false, default: false
    end

    # The author's latest message in a topic, asked before each new one opens.
    create index(:messages, [:topic_id, :author_id, :opened_at])
  end
end
