# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.MoveAutoPunctuationToUsers do
  use Ecto.Migration

  # "Automatic punctuation" moves from Admin → Settings to each user's profile (steward
  # decision, 2026-10-26). A server that had turned it off keeps it off for its members.
  def up do
    alter table(:users) do
      add :auto_punctuation, :boolean, null: false, default: true
    end

    flush()

    execute """
    UPDATE users SET auto_punctuation = false
    WHERE EXISTS (SELECT 1 FROM settings WHERE key = 'gm_auto_punctuation' AND value = 'false')
    """

    execute "DELETE FROM settings WHERE key = 'gm_auto_punctuation'"
  end

  def down do
    alter table(:users) do
      remove :auto_punctuation
    end
  end
end
