# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddForwardedFromToMessages do
  use Ecto.Migration

  # Forward (steward decision, 2026-11-02): a message may carry another message, from any
  # topic, shown in a box above its text. Deleting the original leaves the forward without it;
  # the index lets deleting a topic's messages find their forwards (see "Archive and delete a
  # topic" in CLAUDE.md).
  def change do
    alter table(:messages) do
      add :forwarded_from_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:messages, [:forwarded_from_id])
  end
end
