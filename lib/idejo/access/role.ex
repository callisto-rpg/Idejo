# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Access.Role do
  @moduledoc """
  A role (RP-01, RP-02). Built-in roles are always present; a lower `position` ranks higher.
  Custom roles have a name and an optional colour, and can be renamed, reordered and deleted.

  Role mentions (TP-10, `+role`): `mentionable` lets everyone notify the role's members;
  `mentions_below` lets its members notify any role ranked below it. Member and guest are
  never mentioned, so they take neither.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  @type t :: %__MODULE__{}

  @built_in ~w(owner administrator moderator member guest)

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  schema "roles" do
    field :name, :string
    field :colour, :string
    field :position, :integer
    field :built_in, :boolean, default: false
    field :mentionable, :boolean, default: false
    field :mentions_below, :boolean, default: false

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  The names of the built-in roles, highest rank first.
  """
  @spec built_in_names() :: [String.t()]
  def built_in_names, do: @built_in

  @doc """
  A changeset for a role's name, colour and mention settings. Built-in roles keep their name;
  member and guest take no mention settings. Names are unique ignoring case, so "Member"
  cannot sit next to the built-in member. The colour is `#rrggbb`, or empty for none.
  """
  def changeset(role, attrs) do
    fields =
      cond do
        role.built_in and role.name in ~w(member guest) -> [:colour]
        role.built_in -> [:colour, :mentionable, :mentions_below]
        true -> [:name, :colour, :mentionable, :mentions_below]
      end

    role
    |> cast(attrs, fields)
    # An emptied field is cast to nil, which clears the colour.
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:colour, &(&1 && &1 |> String.trim() |> String.downcase()))
    |> validate_required([:name])
    |> validate_length(:name, max: 40)
    |> validate_format(:colour, ~r/^#[0-9a-f]{6}$/, message: "must look like #3366ff")
    |> validate_name_free()
    |> unique_constraint(:name)
  end

  defp validate_name_free(%Ecto.Changeset{changes: %{name: name}} = changeset) do
    same_name =
      from r in __MODULE__, where: fragment("lower(?)", r.name) == ^String.downcase(name)

    # A role being renamed may keep its own name.
    others =
      case changeset.data.id do
        nil -> same_name
        id -> from r in same_name, where: r.id != ^id
      end

    taken? = Idejo.Repo.exists?(others)

    if taken?, do: add_error(changeset, :name, "is already used by another role"), else: changeset
  end

  defp validate_name_free(changeset), do: changeset
end
