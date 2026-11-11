# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.ApiToken do
  @moduledoc """
  A device token of the official app (AP-09; steward decision, 2026-11-10): long-lived,
  opaque, valid until revoked. Only the SHA-256 hash of the token is stored; `name` is the
  device's name as the app gave it at sign-in.

  Changes to this module get an extra careful human review (DV-06).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_tokens" do
    belongs_to :user, Idejo.Accounts.User
    field :name, :string
    field :scopes, {:array, :string}
    field :token_hash, :binary, redact: true
    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
