# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddPlacementToInfoBoxes do
  use Ecto.Migration

  # Where an info box shows on the home page (steward request, 2026-11-13): before the
  # categories, or in a section (the first, a category group's, or "Other"), at the start
  # or the end of its cards. Existing boxes keep their place: the first section, first.
  def change do
    alter table(:info_boxes) do
      add :placement, :string, null: false, default: "first"
      add :group_id, references(:category_groups, type: :binary_id, on_delete: :nilify_all)
      add :at_end, :boolean, null: false, default: false
    end

    create index(:info_boxes, [:group_id])
  end
end
