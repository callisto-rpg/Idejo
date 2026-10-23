# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddShowNextToNameToRoles do
  use Ecto.Migration

  # Steward decision, 2026-10-23: a role can stay off the line next to its members' names in
  # conversations ("Visible next to name", on for every role at first).
  def change do
    alter table(:roles) do
      add :show_next_to_name, :boolean, null: false, default: true
    end
  end
end
