# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Reaction do
  @moduledoc """
  A user's reaction to a message (TP-17): one emoji, by its name (`"joy"`, `"agree"`). A user
  may add several emoji to one message, each once.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "reactions" do
    belongs_to :message, Idejo.Messages.Message
    belongs_to :user, Idejo.Accounts.User
    field :emoji, :string

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end
end
