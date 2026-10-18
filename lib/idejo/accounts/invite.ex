# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.Invite do
  @moduledoc """
  An invitation to sign up while registration is invite-only (AC-02). Single-use: `used_by`
  is set when someone signs up with it. Valid until `expires_at` (7 days).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @validity_in_days 7

  @primary_key {:code, :string, autogenerate: false}
  @foreign_key_type :binary_id
  schema "invites" do
    belongs_to :creator, Idejo.Accounts.User, foreign_key: :created_by
    belongs_to :user, Idejo.Accounts.User, foreign_key: :used_by
    field :used_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @doc "How long an invite stays valid."
  @spec validity_in_days() :: pos_integer()
  def validity_in_days, do: @validity_in_days

  @doc "Returns `:unused`, `:used` or `:expired`."
  @spec status(t(), DateTime.t()) :: :unused | :used | :expired
  def status(%__MODULE__{used_by: used_by}, _now) when not is_nil(used_by), do: :used

  def status(%__MODULE__{expires_at: expires_at}, now) do
    if DateTime.after?(expires_at, now), do: :unused, else: :expired
  end
end
