# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Reading.Follow do
  @moduledoc """
  A user's follow of a topic (TP-13). `following: false` records an explicit unfollow.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  @foreign_key_type :binary_id
  schema "follows" do
    belongs_to :user, Idejo.Accounts.User, primary_key: true
    belongs_to :topic, Idejo.Forum.Topic, primary_key: true
    field :following, :boolean, default: true

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end
end
