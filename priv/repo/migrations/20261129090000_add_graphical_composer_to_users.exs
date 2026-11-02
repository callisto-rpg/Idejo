# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddGraphicalComposerToUsers do
  use Ecto.Migration

  # "Use the graphical composer" (TP-11; steward decision, 2026-11-02): buttons under the
  # composer, off by default.
  def change do
    alter table(:users) do
      add :graphical_composer, :boolean, null: false, default: false
    end
  end
end
