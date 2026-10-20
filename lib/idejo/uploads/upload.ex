# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Uploads.Upload do
  @moduledoc """
  An uploaded image (TP-12): its file in the uploads directory, type and size.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type :binary_id
  schema "uploads" do
    field :path, :string
    field :mime, :string
    field :size, :integer
    belongs_to :user, Idejo.Accounts.User

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end
end
