# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Access.Role do
  @moduledoc """
  A role (RP-01, RP-02). Built-in roles are always present; a lower `position` ranks higher.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @built_in ~w(owner administrator moderator member guest)

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  schema "roles" do
    field :name, :string
    field :colour, :string
    field :position, :integer
    field :built_in, :boolean, default: false

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  The names of the built-in roles, highest rank first.
  """
  @spec built_in_names() :: [String.t()]
  def built_in_names, do: @built_in
end
