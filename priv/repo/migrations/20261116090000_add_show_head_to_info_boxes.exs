# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddShowHeadToInfoBoxes do
  use Ecto.Migration

  # Info boxes (steward decision, 2026-10-26): "Show title and icon" can hide the card's head.
  def change do
    alter table(:info_boxes) do
      add :show_head, :boolean, null: false, default: true
    end
  end
end
