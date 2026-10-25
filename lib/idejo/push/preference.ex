# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Preference do
  @moduledoc """
  A user's push types (PN-11), for all their browsers: replies (PN-01), @mentions (PN-02),
  +role mentions (PN-03) and followed activity (PN-04), each on by default. A user without a
  row has the defaults.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:user_id, :binary_id, autogenerate: false}
  schema "push_preferences" do
    field :reply, :boolean, default: true
    field :mention, :boolean, default: true
    field :role_mention, :boolean, default: true
    field :followed, :boolean, default: true

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  @doc "A changeset for the four switches."
  def changeset(preference, attrs),
    do: cast(preference, attrs, [:reply, :mention, :role_mention, :followed])
end
