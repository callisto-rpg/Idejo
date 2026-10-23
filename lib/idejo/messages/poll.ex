# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Poll do
  @moduledoc """
  A poll under a message (`!poll`, steward decision, 2026-10-23): a question, its answers
  (`Idejo.Messages.PollOption`), whether several may be chosen, and when it closes. One per
  message (`Idejo.Messages.Polls`).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "polls" do
    field :question, :string
    field :multiple, :boolean, default: false
    field :closes_at, :utc_datetime_usec
    belongs_to :message, Idejo.Messages.Message
    has_many :options, Idejo.Messages.PollOption, preload_order: [asc: :position]

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end
end
