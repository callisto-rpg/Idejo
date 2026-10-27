# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Conversations.Participant do
  @moduledoc """
  A user taking part in a private conversation (steward decision, 2026-10-27): the only
  people who read it.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  @foreign_key_type :binary_id
  schema "conversation_participants" do
    belongs_to :topic, Idejo.Forum.Topic, primary_key: true
    belongs_to :user, Idejo.Accounts.User, primary_key: true

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end
end
