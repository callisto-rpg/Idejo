# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.Tag do
  @moduledoc """
  A topic tag (TP-19): made by administrators, server-wide (no categories) or belonging to
  one or more categories (`tag_categories`; steward decision, 2026-11-14). Its name is unique
  across the server, ignoring case; its slug, made from the name at creation, names it in
  `/tags` links and never changes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "tags" do
    field :name, :string
    field :slug, :string

    many_to_many :categories, Idejo.Forum.Category,
      join_through: "tag_categories",
      on_replace: :delete

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc "A changeset for a new tag: its name. The caller sets the slug and the categories."
  def create_changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name])
    |> validate_name()
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end

  @doc "A changeset for renaming a tag. The slug stays."
  def update_changeset(tag, attrs), do: tag |> cast(attrs, [:name]) |> validate_name()

  defp validate_name(changeset) do
    changeset
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:name, max: 40)
    |> unique_constraint(:name, name: :tags_name_index, message: "is already used by another tag")
  end
end
