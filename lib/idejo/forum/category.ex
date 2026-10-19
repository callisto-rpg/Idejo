# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.Category do
  @moduledoc """
  A category (RP-03): one level, ordered by `position`, reached at `/c/{slug}`.

  The slug is chosen at creation and then kept, so links to the category never break when it
  is renamed. Every category has a stable URI (FD-01).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "categories" do
    field :uri, :string
    field :slug, :string
    field :name, :string
    field :description, :string, default: ""
    field :position, :integer
    field :visibility, :string, default: "public"
    # Sub-categories wait for v1 (RP-05); the column exists but is never set in v0.1.
    belongs_to :parent, __MODULE__

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  A changeset for a new category: name, description and, optionally, the slug. The caller
  sets `id`, `uri` and `position`.
  """
  def create_changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :slug])
    |> validate_name_and_description()
    |> update_change(:slug, &(&1 && String.trim(&1)))
    |> validate_required([:id, :uri, :position, :slug])
    |> validate_length(:slug, max: 60)
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "may only contain lowercase letters, digits and single dashes"
    )
    |> unsafe_validate_unique(:slug, Idejo.Repo, message: "is already used by another category")
    |> unique_constraint(:slug, message: "is already used by another category")
  end

  @doc """
  A changeset for renaming a category or changing its description. The slug stays.
  """
  def update_changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description])
    |> validate_name_and_description()
  end

  defp validate_name_and_description(changeset) do
    changeset
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:description, &(&1 && String.trim(&1)))
    # An emptied description is cast to nil; the column keeps "" instead.
    |> then(&if(get_field(&1, :description), do: &1, else: put_change(&1, :description, "")))
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 500)
  end
end
