# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateCategoryGroups do
  use Ecto.Migration

  # RP-03 (steward decision, 2026-10-23): administrators group categories under named
  # headings, in order. A category may belong to no group; deleting a group keeps its
  # categories, ungrouped.
  def change do
    create table(:category_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:category_groups, ["lower(name)"], name: :category_groups_name_index)

    alter table(:categories) do
      add :group_id, references(:category_groups, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:categories, [:group_id])
  end
end
