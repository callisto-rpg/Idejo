# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.UserIdentity do
  @moduledoc """
  A link between an account and a person at an OpenID Connect provider (AC-09): the
  provider's `issuer` and its `subject` (`sub`) for them, unique together. Never an email,
  never a token.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_identities" do
    belongs_to :user, Idejo.Accounts.User
    field :issuer, :string
    field :subject, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "A new link of `user_id` to `issuer` and `subject`."
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :issuer, :subject])
    |> validate_required([:user_id, :issuer, :subject])
    |> validate_length(:issuer, max: 255)
    |> validate_length(:subject, max: 255)
    |> unique_constraint([:issuer, :subject])
  end
end
