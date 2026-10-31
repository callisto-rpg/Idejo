# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMessageControlsToUsers do
  use Ecto.Migration

  # Whether a message's actions (React, Edit, Reply…) always show, on touch screens and on
  # screens that point, instead of on a tap or hover (steward decision, 2026-10-31).
  def change do
    alter table(:users) do
      add :controls_on_mobile, :boolean, null: false, default: false
      add :controls_on_desktop, :boolean, null: false, default: false
    end
  end
end
