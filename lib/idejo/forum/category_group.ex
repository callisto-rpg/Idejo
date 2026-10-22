# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.CategoryGroup do
  @moduledoc """
  A group of categories (RP-03; steward decision, 2026-10-23): a named heading over its
  categories on the home page and in the sidebar, ordered by `position`. Names are unique,
  ignoring case.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  schema "category_groups" do
    field :name, :string
    field :position, :integer
    has_many :categories, Idejo.Forum.Category, foreign_key: :group_id

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc "A changeset for a group's name. The caller sets the position."
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
    |> unique_constraint(:name,
      name: :category_groups_name_index,
      message: "is already used by another group"
    )
  end
end
