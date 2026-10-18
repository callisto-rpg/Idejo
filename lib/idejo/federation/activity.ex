# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Federation.Activity do
  @moduledoc """
  One row of the activities outbox (FD-02): an actor did `verb` to an object, optionally
  within a target.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @verbs ~w(create update delete announce)

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  schema "activities" do
    field :actor_uri, :string
    field :verb, :string
    field :object_uri, :string
    field :target_uri, :string
    field :payload, :map, default: %{}

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @doc false
  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:actor_uri, :verb, :object_uri, :target_uri, :payload])
    |> validate_required([:actor_uri, :verb, :object_uri])
    |> validate_inclusion(:verb, @verbs)
  end
end
