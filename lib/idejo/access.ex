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
  alias Idejo.Audit

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

  ## Role editor (RP-02)

  # Ranks that never change, so the order cannot put anyone above the owner or below guest.
  @fixed_top ~w(owner administrator)
  @fixed_bottom ~w(guest)

  @doc """
  Returns true when a role can move in the order: every role but owner and administrator
  (always on top) and guest (always last).
  """
  @spec movable?(Role.t()) :: boolean()
  def movable?(%Role{built_in: true, name: name})
      when name in @fixed_top or name in @fixed_bottom,
      do: false

  def movable?(%Role{}), do: true

  @doc """
  Returns a changeset for the role form.
  """
  def change_role(%Role{} = role, attrs \\ %{}), do: Role.changeset(role, attrs)

  @doc """
  Creates a custom role, as `admin`, ranked just above guest. Audited as `role.create`.
  """
  @spec create_role(User.t(), map()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def create_role(%User{} = admin, attrs) do
    Repo.transact(fn ->
      lock_roles()
      guest = built_in_role!(:guest)

      with {:ok, role} <- Repo.insert(Role.changeset(%Role{position: guest.position}, attrs)),
           {:ok, _} <- Repo.update(Ecto.Changeset.change(guest, position: guest.position + 1)),
           {:ok, _} <- Audit.record(admin, "role.create", nil, role_snapshot(role)) do
        {:ok, role}
      end
    end)
  end

  @doc """
  Renames a custom role or changes the colour of any role, as `admin`. Audited as
  `role.update` with the old and new values.
  """
  @spec update_role(User.t(), Role.t(), map()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def update_role(%User{} = admin, %Role{} = role, attrs) do
    case Role.changeset(role, attrs) do
      %Ecto.Changeset{changes: changes} when changes == %{} -> {:ok, role}
      changeset -> Repo.transact(fn -> save_role(admin, role, changeset) end)
    end
  end

  defp save_role(admin, role, changeset) do
    with {:ok, updated} <- Repo.update(changeset),
         {:ok, _} <-
           Audit.record(admin, "role.update", role_snapshot(role), role_snapshot(updated)) do
      {:ok, updated}
    end
  end

  @doc """
  Moves a role one place up (higher rank) or down, as `admin`, swapping it with its neighbour.
  Audited as `role.reorder`. Owner, administrator and guest do not move, and nothing moves
  past them.
  """
  @spec move_role(User.t(), Role.t(), :up | :down) ::
          {:ok, [Role.t()]} | {:error, :fixed_rank}
  def move_role(%User{} = admin, %Role{} = role, direction) when direction in [:up, :down] do
    Repo.transact(fn ->
      lock_roles()
      roles = list_roles()

      case neighbours(roles, role, direction) do
        {role, neighbour} -> swap_positions(admin, roles, role, neighbour)
        nil -> {:error, :fixed_rank}
      end
    end)
  end

  # The role and the one it would swap with, or nil when either cannot move.
  defp neighbours(roles, role, direction) do
    with index when is_integer(index) <- Enum.find_index(roles, &(&1.id == role.id)),
         target = if(direction == :up, do: index - 1, else: index + 1),
         # Enum.at/2 counts negative indexes from the end, so stop at the top first.
         true <- target >= 0,
         %Role{} = neighbour <- Enum.at(roles, target),
         role = Enum.at(roles, index),
         true <- movable?(role) and movable?(neighbour) do
      {role, neighbour}
    else
      _ -> nil
    end
  end

  defp swap_positions(admin, roles_before, role, neighbour) do
    with {:ok, _} <- Repo.update(Ecto.Changeset.change(role, position: neighbour.position)),
         {:ok, _} <- Repo.update(Ecto.Changeset.change(neighbour, position: role.position)),
         roles_after = list_roles(),
         {:ok, _} <-
           Audit.record(admin, "role.reorder", %{"order" => order_names(roles_before)}, %{
             "order" => order_names(roles_after)
           }) do
      {:ok, roles_after}
    end
  end

  defp order_names(roles), do: Enum.map(roles, & &1.name)

  @doc """
  Deletes a custom role, as `admin`. The users who held it simply lose it; the roles below
  move up one place. Audited as `role.delete`. Built-in roles cannot be deleted.
  """
  @spec delete_role(User.t(), Role.t()) :: {:ok, Role.t()} | {:error, :built_in}
  def delete_role(%User{}, %Role{built_in: true}), do: {:error, :built_in}

  def delete_role(%User{} = admin, %Role{} = role) do
    Repo.transact(fn ->
      lock_roles()

      with {:ok, deleted} <- Repo.delete(role),
           {_, _} <-
             Repo.update_all(from(r in Role, where: r.position > ^role.position),
               inc: [position: -1]
             ),
           {:ok, _} <- Audit.record(admin, "role.delete", role_snapshot(role), nil) do
        {:ok, deleted}
      end
    end)
  end

  @doc """
  Counts how many users hold each role, as a map from role id. For the role editor.
  """
  @spec holder_counts() :: %{Ecto.UUID.t() => non_neg_integer()}
  def holder_counts do
    Repo.all(from ur in UserRole, group_by: ur.role_id, select: {ur.role_id, count()})
    |> Map.new()
  end

  defp role_snapshot(role), do: Audit.snapshot(role, [:name, :colour, :position])

  # Positions are rewritten as a whole; one change at a time.
  defp lock_roles, do: Repo.query!("LOCK TABLE roles IN SHARE ROW EXCLUSIVE MODE")
end
