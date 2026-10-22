# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.Tag do
  @moduledoc """
  A topic tag (TP-19): made by administrators, server-wide (`category_id` nil) or belonging
  to one category. Its name is unique across the server, ignoring case; its slug, made from
  the name at creation, names it in `/tags` links and never changes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "tags" do
    field :name, :string
    field :slug, :string
    belongs_to :category, Idejo.Forum.Category

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc "A changeset for a new tag: its name and where it belongs. The caller sets the slug."
  def create_changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :category_id])
    |> validate_name()
    |> validate_required([:slug])
    |> foreign_key_constraint(:category_id)
    |> unique_constraint(:slug)
  end

  @doc "A changeset for renaming a tag. The slug and the category stay."
  def update_changeset(tag, attrs), do: tag |> cast(attrs, [:name]) |> validate_name()

  defp validate_name(changeset) do
    changeset
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:name, max: 40)
    |> unique_constraint(:name, name: :tags_name_index, message: "is already used by another tag")
  end
end
