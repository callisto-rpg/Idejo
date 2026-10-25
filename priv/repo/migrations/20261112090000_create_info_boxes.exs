# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateInfoBoxes do
  use Ecto.Migration

  # Steward decision, 2026-10-25: cards of the administrators' own text beside the home
  # page's categories, with an icon and a colour like theirs.
  def change do
    create table(:info_boxes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :icon, :string
      add :colour, :string
      add :body_md, :text, null: false, default: ""
      add :body_html, :text, null: false, default: ""
      add :position, :integer, null: false

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end
  end
end
