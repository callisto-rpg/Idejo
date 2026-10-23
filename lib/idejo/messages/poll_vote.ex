# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.PollVote do
  @moduledoc """
  A user's choice of one answer of a poll; several rows when the poll takes several answers.
  Votes are never shown by name: readers see counts only.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "poll_votes" do
    belongs_to :poll, Idejo.Messages.Poll
    belongs_to :option, Idejo.Messages.PollOption
    belongs_to :user, Idejo.Accounts.User

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end
end
