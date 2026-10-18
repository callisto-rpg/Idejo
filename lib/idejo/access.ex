# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Access do
  @moduledoc """
  Roles (RP-01) and, from RP-04, the permission check `can?/3`.

  The built-in roles owner, administrator, moderator, member and guest always exist; the
  database refuses to delete or rename them. Visitors without an account and users who have
  not verified their email address act as guest. Verifying an address grants member, and a
  verified user who holds no role at all acts as member.

  Rights from several roles combine with "allow wins" (decided 2026-10-19; replaces "deny
  wins" in RP-06): if any of a user's roles allows a right, the user has it.
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
  Returns true when the user may use the admin panel (AD-02): they hold owner or
  administrator and have verified their email address.
  """
  @spec administrator?(User.t() | nil) :: boolean()
  def administrator?(nil), do: false

  def administrator?(%User{} = user) do
    Enum.any?(roles_of(user), &(&1.built_in and &1.name in ~w(owner administrator)))
  end

  @doc """
  Returns the roles of several users at once, as a map from user id to the same list
  `roles_of/1` gives. Used by lists such as the admin users page.
  """
  @spec roles_of_users([User.t()]) :: %{Ecto.UUID.t() => [Role.t(), ...]}
  def roles_of_users(users) do
    ids = for %User{confirmed_at: %DateTime{}, id: id} <- users, do: id

    held =
      Repo.all(
        from r in Role,
          join: ur in UserRole,
          on: ur.role_id == r.id,
          where: ur.user_id in ^ids,
          select: {ur.user_id, r}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    guest = built_in_role!(:guest)
    member = built_in_role!(:member)

    Map.new(users, fn
      %User{confirmed_at: nil, id: id} ->
        {id, [guest]}

      %User{id: id} ->
        roles = [member | Map.get(held, id, [])] |> Enum.uniq_by(& &1.id)
        {id, Enum.sort_by(roles, &{&1.position, &1.name})}
    end)
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
  user gets the roles they hold, or member if they hold none, so the list is never empty.
  """
  @spec roles_of(User.t() | nil) :: [Role.t()]
  def roles_of(nil), do: [built_in_role!(:guest)]
  def roles_of(%User{confirmed_at: nil}), do: [built_in_role!(:guest)]

  def roles_of(%User{id: user_id}) do
    roles =
      Repo.all(
        from r in Role,
          join: ur in UserRole,
          on: ur.role_id == r.id,
          where: ur.user_id == ^user_id,
          order_by: [asc: r.position, asc: r.name]
      )

    # No user is ever without a role: a verified user holding none acts as member.
    case roles do
      [] -> [built_in_role!(:member)]
      roles -> roles
    end
  end

  @doc """
  Gives a role to a user. Giving a role the user already holds is a no-op.

  Guest cannot be given: it is never held, only acted as.
  """
  @spec grant_role(User.t(), Role.t()) :: :ok | {:error, :guest_is_implicit}
  def grant_role(%User{}, %Role{built_in: true, name: "guest"}), do: {:error, :guest_is_implicit}

  def grant_role(%User{id: user_id}, %Role{id: role_id}) do
    Repo.insert_all(UserRole, [%{user_id: user_id, role_id: role_id}], on_conflict: :nothing)
    :ok
  end

  @doc """
  Called when a user verifies their email address (AC-01): grants member.
  """
  @spec grant_verified_roles(User.t()) :: :ok
  def grant_verified_roles(%User{} = user), do: grant_role(user, built_in_role!(:member))
end
