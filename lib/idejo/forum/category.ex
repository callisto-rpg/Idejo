# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.Category do
  @moduledoc """
  A category (RP-03): one level, ordered by `position`, reached at `/c/{slug}`.

  The slug is chosen at creation and then kept, so links to the category never break when it
  is renamed. Every category has a stable URI (FD-01). It may have an icon
  (`Idejo.Forum.CategoryIcons`) and a colour, `#rrggbb` (steward decision, 2026-10-23).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Idejo.Forum.CategoryIcons

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "categories" do
    field :uri, :string
    field :slug, :string
    field :name, :string
    field :description, :string, default: ""
    field :icon, :string
    field :colour, :string
    field :position, :integer
    field :visibility, :string, default: "public"
    # The one built-in Archive category (RP-03, TP-14), made by `Idejo.Forum` on first use.
    field :archive, :boolean, default: false
    # Sub-categories wait for v1 (RP-05); the column exists but is never set in v0.1.
    belongs_to :parent, __MODULE__
    # RP-03: the group it is listed under, if any (steward decision, 2026-10-23).
    belongs_to :group, Idejo.Forum.CategoryGroup, type: Ecto.UUID

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  A changeset for a new category: name, description and, optionally, the slug. The caller
  sets `id`, `uri` and `position`.
  """
  def create_changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :slug, :icon, :colour, :group_id])
    |> validate_name_and_description()
    |> validate_look()
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
  A changeset for renaming a category or changing its description, icon or colour. The slug
  stays.
  """
  def update_changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :icon, :colour, :group_id])
    |> validate_name_and_description()
    |> validate_look()
  end

  # An icon from the set, or none; a colour as #rrggbb, or none (the tint from the id).
  defp validate_look(changeset) do
    changeset
    |> update_change(:colour, &(&1 && &1 |> String.trim() |> String.downcase()))
    |> validate_format(:colour, ~r/^#[0-9a-f]{6}$/, message: "must look like #3366ff")
    |> foreign_key_constraint(:group_id, message: "is not a group")
    |> validate_change(:icon, fn :icon, icon ->
      if CategoryIcons.icon?(icon), do: [], else: [icon: "is not one of the icons"]
    end)
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
