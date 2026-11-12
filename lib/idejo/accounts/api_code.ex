# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.ApiCode do
  @moduledoc """
  An authorization code of the official app's sign-in (AP-08): single use, valid 60 seconds,
  bound to the user, the PKCE challenge, the scopes and the device name. Only its SHA-256
  hash is stored. `token_id` is the token it was exchanged for, so a reused code can revoke
  it (RFC 6749 §4.1.2).

  Changes to this module get an extra careful human review (DV-06).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_codes" do
    belongs_to :user, Idejo.Accounts.User
    field :code_hash, :binary, redact: true
    field :challenge, :string
    field :scopes, {:array, :string}
    field :device_name, :string
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec
    field :token_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
