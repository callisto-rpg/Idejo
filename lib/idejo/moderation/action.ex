# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Moderation.Action do
  @moduledoc """
  One moderator action in the moderation log (MO-03): who did what to which message, topic or
  user, why, and when.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "mod_actions" do
    field :action, :string
    field :target_type, :string
    field :target_id, :binary_id
    field :category_id, :binary_id
    field :reason, :string
    field :details, :map, default: %{}
    belongs_to :moderator, Idejo.Accounts.User

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end
end
