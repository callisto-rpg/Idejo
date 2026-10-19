# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  # RP-03, MVP §6. One level only: parent_id exists for sub-categories in v1 but stays unused.
  # visibility is the preset (public, members, restricted) that RP-04 turns into view rights.
  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :uri, :string, null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :text, null: false, default: ""
      add :position, :integer, null: false
      add :visibility, :string, null: false, default: "public"
      add :parent_id, references(:categories, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:categories, [:uri])
    create unique_index(:categories, [:slug])
    create index(:categories, [:position])
  end
end
