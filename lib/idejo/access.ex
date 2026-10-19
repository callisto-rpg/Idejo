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

  alias Idejo.Access.{CategoryPermission, Role, UserRole}
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Forum.Category

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

  ## Category rights (RP-04)

  @doc """
  The rights of v0.1: `:view`, `:start` (topics), `:post` and `:moderate`.
  """
  @spec rights() :: [atom()]
  def rights, do: CategoryPermission.rights()

  @doc """
  Returns true when the visitor or user has `right` in `category`.

  Owners and administrators always have every right. Otherwise each of the user's roles
  (`roles_of/1`) gets the category's own setting for that role, or, when unset there, the
  role's server-wide setting; a deny on the category overrides the server-wide allow for that
  role. Across roles, **allow wins**: one role allowing is enough (RP-06).
  """
  @spec can?(User.t() | nil, atom(), Category.t()) :: boolean()
  def can?(user, right, %Category{id: category_id})
      when right in [:view, :start, :post, :moderate] do
    from(c in Category, where: c.id == ^category_id)
    |> where_allowed(user, right)
    |> Repo.exists?()
  end

  @doc """
  Narrows a query on categories to those where the visitor or user has `right`, in the
  database: lists and search filter this way, never after loading. Same rule as `can?/3`.
  """
  @spec where_allowed(Ecto.Queryable.t(), User.t() | nil, atom()) :: Ecto.Query.t()
  def where_allowed(query, user, right) when right in [:view, :start, :post, :moderate] do
    query = from(c in query, as: :category)

    if administrator?(user) do
      query
    else
      role_ids = Enum.map(roles_of(user), & &1.id)
      right = Atom.to_string(right)

      from c in query,
        where:
          exists(
            from r in Role,
              left_join: own in CategoryPermission,
              on:
                own.category_id == parent_as(:category).id and own.role_id == r.id and
                  own.right == ^right,
              left_join: server in CategoryPermission,
              on:
                is_nil(server.category_id) and server.role_id == r.id and server.right == ^right,
              where: r.id in ^role_ids and coalesce(own.effect, server.effect) == "allow"
          )
    end
  end

  @doc """
  Returns the permission settings of a category, or the server-wide ones (`:server`), as a
  map from `{role_id, right}` to `:allow` or `:deny`. Unset rights are missing.
  """
  @spec permissions(Category.t() | :server) :: %{{Ecto.UUID.t(), atom()} => :allow | :deny}
  def permissions(scope) do
    scope
    |> permissions_query()
    |> Repo.all()
    |> Map.new(fn p ->
      {{p.role_id, String.to_existing_atom(p.right)}, String.to_existing_atom(p.effect)}
    end)
  end

  defp permissions_query(:server), do: from(p in CategoryPermission, where: is_nil(p.category_id))

  defp permissions_query(%Category{id: id}),
    do: from(p in CategoryPermission, where: p.category_id == ^id)

  @doc """
  Sets one role's right on a category or server-wide, as `admin`: `:allow`, `:deny` or
  `:unset` (removes the setting). Audited as `permission.update` (SP-06).

  Owner and administrator always have every right, so they take no settings
  (`{:error, :always_all_rights}`); server-wide, a right is only allowed or unset
  (`{:error, :no_server_deny}`): deny exists to override the server-wide allow on one category.
  """
  @spec set_permission(
          User.t(),
          Role.t(),
          Category.t() | :server,
          atom(),
          :allow | :deny | :unset
        ) ::
          {:ok, :allow | :deny | :unset} | {:error, :always_all_rights | :no_server_deny}
  def set_permission(%User{}, %Role{built_in: true, name: name}, _scope, _right, _effect)
      when name in @all_rights,
      do: {:error, :always_all_rights}

  def set_permission(%User{}, %Role{}, :server, _right, :deny), do: {:error, :no_server_deny}

  def set_permission(%User{} = admin, %Role{} = role, scope, right, effect)
      when right in [:view, :start, :post, :moderate] and effect in [:allow, :deny, :unset] do
    Repo.transact(fn ->
      existing =
        Repo.one(
          from p in permissions_query(scope),
            where: p.role_id == ^role.id and p.right == ^Atom.to_string(right),
            lock: "FOR UPDATE"
        )

      before = if existing, do: String.to_existing_atom(existing.effect), else: :unset

      with :ok <- write_permission(existing, role, scope, right, effect),
           {:ok, _} <- audit_permission(admin, role, scope, right, before, effect) do
        {:ok, effect}
      end
    end)
  end

  defp write_permission(nil, _role, _scope, _right, :unset), do: :ok

  defp write_permission(%CategoryPermission{} = existing, _role, _scope, _right, :unset) do
    with {:ok, _} <- Repo.delete(existing), do: :ok
  end

  defp write_permission(nil, role, scope, right, effect) do
    category_id = if scope == :server, do: nil, else: scope.id

    with {:ok, _} <-
           Repo.insert(%CategoryPermission{
             category_id: category_id,
             role_id: role.id,
             right: Atom.to_string(right),
             effect: Atom.to_string(effect)
           }),
         do: :ok
  end

  defp write_permission(%CategoryPermission{} = existing, _role, _scope, _right, effect) do
    with {:ok, _} <- Repo.update(Ecto.Changeset.change(existing, effect: Atom.to_string(effect))),
         do: :ok
  end

  # An unchanged setting writes no entry.
  defp audit_permission(_admin, _role, _scope, _right, same, same), do: {:ok, :unchanged}

  defp audit_permission(admin, role, scope, right, before, effect) do
    where = %{
      "role" => role.name,
      "category" => if(scope == :server, do: "(server)", else: scope.slug),
      "right" => Atom.to_string(right)
    }

    Audit.record(
      admin,
      "permission.update",
      Map.put(where, "effect", Atom.to_string(before)),
      Map.put(where, "effect", Atom.to_string(effect))
    )
  end
end
