# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.TopicIcon do
  @moduledoc """
  An icon a topical topic may show in place of its starter (Topic Type, steward request,
  2026-11-07): an image administrators upload (`Idejo.Uploads.store_icon/2`) with a name,
  its text alternative, in their order. Managed by `Idejo.Forum.TopicIcons`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "topic_icons" do
    belongs_to :upload, Idejo.Uploads.Upload
    field :name, :string
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @doc "The icon's name: required, 60 characters at most."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(icon, attrs) do
    icon
    |> cast(attrs, [:name])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
  end
end
