# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Audit.Entry do
  @moduledoc """
  One row of the admin audit log (SP-06): who changed what, with the values before and after.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7, precision: :monotonic]}
  @foreign_key_type :binary_id
  schema "audit_log" do
    belongs_to :admin, Idejo.Accounts.User
    field :change, :string
    field :before, :map
    field :after, :map

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:admin_id, :change, :before, :after])
    |> validate_required([:change])
    |> validate_format(:change, ~r/^[a-z_]+\.[a-z_]+$/,
      message: "must look like \"subject.action\", e.g. \"role.create\""
    )
    |> foreign_key_constraint(:admin_id)
  end
end
