# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMessagesModeratorEdited do
  use Ecto.Migration

  # "message edited by a moderator" (steward request, 2026-11-09): set when a moderator edits
  # someone else's message (MO-02), shown to every reader under it. Messages edited by a
  # moderator before this keep false: the log (MO-03) still names them.
  def change do
    alter table(:messages) do
      add :moderator_edited, :boolean, null: false, default: false
    end
  end
end
