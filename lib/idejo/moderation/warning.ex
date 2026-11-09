# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Moderation.Warning do
  @moduledoc """
  A warning (MO-02): who was warned, by which moderator, for which message (in which
  category), why, and when they saw it (nil until they acknowledge it).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "warnings" do
    field :category_id, Ecto.UUID
    field :reason, :string
    field :seen_at, :utc_datetime
    belongs_to :user, Idejo.Accounts.User
    belongs_to :moderator, Idejo.Accounts.User
    belongs_to :message, Idejo.Messages.Message

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
