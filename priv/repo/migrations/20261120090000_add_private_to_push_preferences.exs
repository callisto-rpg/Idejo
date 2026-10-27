# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddPrivateToPushPreferences do
  use Ecto.Migration

  # Pushes for private messages (steward decision, 2026-10-27), a switch like PN-11's.
  def change do
    alter table(:push_preferences) do
      add :private, :boolean, null: false, default: true
    end
  end
end
