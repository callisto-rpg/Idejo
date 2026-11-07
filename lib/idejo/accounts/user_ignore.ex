# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.UserIgnore do
  @moduledoc """
  AC-06: `user_id` ignores `ignored_id`, whose messages are collapsed for them. Seen only by
  the one who ignores; the ignored user is never told.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  @foreign_key_type :binary_id
  schema "user_ignores" do
    belongs_to :user, Idejo.Accounts.User, primary_key: true
    belongs_to :ignored, Idejo.Accounts.User, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
