# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Reading.ReadPosition do
  @moduledoc """
  A user's read position in a topic (TP-07): the last message they have seen there.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  @foreign_key_type :binary_id
  schema "read_positions" do
    belongs_to :user, Idejo.Accounts.User, primary_key: true
    belongs_to :topic, Idejo.Forum.Topic, primary_key: true
    belongs_to :last_read_message, Idejo.Messages.Message

    timestamps(type: :utc_datetime_usec, inserted_at: false)
  end
end
