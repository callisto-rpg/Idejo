# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Version do
  @moduledoc """
  An earlier version of a message (GM-11): its full Markdown before a commit changed text
  already sent, with the time that commit replaced it.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "message_versions" do
    field :body_md, :string
    belongs_to :message, Idejo.Messages.Message

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end
end
