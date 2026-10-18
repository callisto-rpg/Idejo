# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Access do
  @moduledoc """
  Roles (RP-01) and, from RP-04, the permission check `can?/3`.

  The built-in roles owner, administrator, moderator, member and guest always exist; the
  database refuses to delete or rename them.

  Guest and member are implicit and never stored in `user_roles`: visitors without an
  account and users who have not verified their email address act as guest; every verified
  user holds member, whatever other roles they hold. So nobody is ever without a role.
  """

  import Ecto.Query, warn: false
  alias Idejo.Repo

  alias Idejo.Access.{Role, UserRole}
  alias Idejo.Accounts.User

  @type built_in :: :owner | :administrator | :moderator | :member | :guest

  @doc """
  Lists all roles, highest rank first.
  """
  @spec list_roles() :: [Role.t()]
  def list_roles do
    Repo.all(from r in Role, order_by: [asc: r.position, asc: r.name])
  end

  @doc """
  Gets a built-in role.
  """
  @spec built_in_role!(built_in()) :: Role.t()
  def built_in_role!(name) when is_atom(name) do
    name = Atom.to_string(name)
    true = name in Role.built_in_names()
    Repo.get_by!(Role, name: name, built_in: true)
  end

  @doc """
  Returns the roles a visitor or user acts with, highest rank first.

  `nil` (a visitor) and a user with an unverified email address get only guest. A verified
  user gets member plus every role they hold.
  """
  @spec roles_of(User.t() | nil) :: [Role.t(), ...]
  def roles_of(nil), do: [built_in_role!(:guest)]
  def roles_of(%User{confirmed_at: nil}), do: [built_in_role!(:guest)]

  def roles_of(%User{id: user_id}) do
    Repo.all(
      from r in Role,
        left_join: ur in UserRole,
        on: ur.role_id == r.id and ur.user_id == ^user_id,
        where: not is_nil(ur.user_id) or (r.built_in and r.name == "member"),
        order_by: [asc: r.position, asc: r.name]
    )
  end

  @doc """
  Gives a role to a user. Giving a role the user already holds is a no-op.

  Guest and member cannot be given: they follow from whether the email is verified.
  """
  @spec grant_role(User.t(), Role.t()) :: :ok | {:error, :implicit_role}
  def grant_role(%User{}, %Role{built_in: true, name: name}) when name in ~w(guest member),
    do: {:error, :implicit_role}

  def grant_role(%User{id: user_id}, %Role{id: role_id}) do
    Repo.insert_all(UserRole, [%{user_id: user_id, role_id: role_id}], on_conflict: :nothing)
    :ok
  end
end
