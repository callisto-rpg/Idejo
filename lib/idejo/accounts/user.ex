# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.User do
  @moduledoc """
  A local account (AC-01): email and password, a unique username for @mentions and a
  display name. `confirmed_at` is set once the email address is verified.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "users" do
    field :uri, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :username, :string
    field :display_name, :string
    field :status, :string, default: "active"
    field :origin, :string, default: "local"
    field :confirmed_at, :utc_datetime

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  A changeset for signing up. The caller sets `id` and `uri` (FD-01).

  ## Options

    * `:hash_password` - see `password_changeset/3`. Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :username, :display_name, :password])
    |> validate_required([:id, :uri])
    |> validate_email()
    |> validate_username()
    |> validate_display_name()
    |> validate_password(opts)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Idejo.Repo)
    |> unique_constraint(:email)
  end

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> validate_format(:username, ~r/^[A-Za-z0-9_]+$/,
      message: "may only contain letters, digits and underscores"
    )
    |> validate_length(:username, min: 3, max: 30)
    |> unsafe_validate_unique(:username, Idejo.Repo)
    |> unique_constraint(:username)
  end

  defp validate_display_name(changeset) do
    changeset
    |> update_change(:display_name, &String.trim/1)
    |> validate_required([:display_name])
    |> validate_length(:display_name, max: 60)
  end

  @doc """
  A changeset for setting the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash.

  ## Options

    * `:hash_password` - Hashes the password with Argon2id so it can be stored securely
      and clears the plain password to prevent leaks in the logs. Set to `false` for
      validation only. Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Marks the email address as verified by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now(:second))
  end

  @doc """
  Verifies the password.

  If there is no user, `Argon2.no_user_verify/0` runs to avoid timing attacks.
  """
  def valid_password?(%__MODULE__{password_hash: password_hash}, password)
      when is_binary(password_hash) and byte_size(password) > 0 do
    Argon2.verify_pass(password, password_hash)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end
end
