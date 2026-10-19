# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Access.CategoryPermission do
  @moduledoc """
  One right of one role (RP-04): on a category, or server-wide when `category_id` is nil.
  `effect` is `"allow"` or `"deny"`; no row means unset.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @rights ~w(view start post moderate)a

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "category_permissions" do
    belongs_to :category, Idejo.Forum.Category
    belongs_to :role, Idejo.Access.Role
    field :right, :string
    field :effect, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The rights of v0.1: view, start topics, post, moderate."
  @spec rights() :: [atom()]
  def rights, do: @rights
end
