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

  # Built-in roles that always have every right and never depend on email verification.
  @all_rights ~w(owner administrator)

  @doc """
  Lists all roles, highest rank first.
  """
  @spec list_roles() :: [Role.t()]
  def list_roles do
    Repo.all(from r in Role, order_by: [asc: r.position, asc: r.name])
  end

  @doc """
  Returns true when the user holds owner or administrator.

  Owners and administrators always have every right and can always use the admin panel
  (AD-02), whatever their other roles, the permission grid or the state of their email
  verification, so they can never lock themselves out. `can?/3` must check this first.
  """
  @spec administrator?(User.t() | nil) :: boolean()
  def administrator?(nil), do: false

  def administrator?(%User{id: user_id}) do
    Repo.exists?(
      from r in Role,
        join: ur in UserRole,
        on: ur.role_id == r.id,
        where: ur.user_id == ^user_id and r.built_in and r.name in @all_rights
    )
  end

  @doc """
  Returns the roles of several users at once, as a map from user id to the same list
  `roles_of/1` gives. Used by lists such as the admin users page.
  """
  @spec roles_of_users([User.t()]) :: %{Ecto.UUID.t() => [Role.t(), ...]}
  def roles_of_users(users) do
    ids = Enum.map(users, & &1.id)

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

    Map.new(users, fn user ->
      held = Map.get(held, user.id, [])

      # Unverified users act as guest, but keep owner and administrator (never locked out).
      roles =
        case user do
          %User{confirmed_at: nil} -> [guest | Enum.filter(held, &(&1.name in @all_rights))]
          _ -> [member | held]
        end

      {user.id, roles |> Enum.uniq_by(& &1.id) |> Enum.sort_by(&{&1.position, &1.name})}
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

  `nil` (a visitor) gets only guest. A user with an unverified email address acts as guest,
  but keeps owner or administrator if they hold it, so owners and administrators are never
  shown or treated as less than they are. A verified user gets member plus every role they
  hold.
  """
  @spec roles_of(User.t() | nil) :: [Role.t(), ...]
  def roles_of(nil), do: [built_in_role!(:guest)]
  def roles_of(%User{id: id} = user), do: Map.fetch!(roles_of_users([user]), id)

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
