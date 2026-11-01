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

  @grid_topic "access:permissions"

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
  Returns true when the user moderates the whole server: an owner or administrator, or one
  of their roles allows `:moderate` server-wide (the built-in moderator does). Server-wide
  actions such as bans (MO-02) need it; moderating one category is not enough.
  """
  @spec server_moderator?(User.t() | nil) :: boolean()
  def server_moderator?(nil), do: false

  def server_moderator?(%User{} = user) do
    roles = roles_of(user)
    role_ids = Enum.map(roles, & &1.id)

    all_rights?(roles) or
      Repo.exists?(
        from p in CategoryPermission,
          where:
            is_nil(p.category_id) and p.role_id in ^role_ids and p.right == "moderate" and
              p.effect == "allow"
      )
  end

  @doc """
  Returns the roles of several users at once, as a map from user id to the same list
  `roles_of/1` gives. Used by lists such as the admin users page.
  """
  @spec roles_of_users([User.t()]) :: %{Ecto.UUID.t() => [Role.t()]}
  def roles_of_users(users) do
    ids = Enum.map(users, & &1.id)

    # One query: the roles the users hold, with guest and member, which nobody holds.
    rows =
      Repo.all(
        from r in Role,
          left_join: ur in UserRole,
          on: ur.role_id == r.id and ur.user_id in ^ids,
          where: not is_nil(ur.user_id) or (r.built_in and r.name in ["guest", "member"]),
          select: {ur.user_id, r}
      )

    held =
      for({user_id, role} <- rows, user_id != nil, do: {user_id, role})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    guest = implicit_role!(rows, "guest")
    member = implicit_role!(rows, "member")

    Map.new(users, fn user ->
      held = Map.get(held, user.id, [])

      # Unverified users act as guest, but keep owner and administrator (never locked out).
      # Server accounts (automessages' senders) hold none: they never act on their own, and
      # no role shows next to their name (steward decision, 2026-11-02).
      roles =
        case user do
          %User{status: "system"} -> []
          %User{confirmed_at: nil} -> [guest | Enum.filter(held, &(&1.name in @all_rights))]
          _ -> [member | held]
        end

      {user.id, roles |> Enum.uniq_by(& &1.id) |> Enum.sort_by(&{&1.position, &1.name})}
    end)
  end

  defp implicit_role!(rows, name) do
    Enum.find_value(rows, fn {_user_id, role} -> role.built_in and role.name == name and role end) ||
      raise Ecto.NoResultsError, queryable: Role
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
  hold. A server account (`status: "system"`, `Idejo.Messages.Automessages`) gets none.
  """
  @spec roles_of(User.t() | nil) :: [Role.t()]
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

  ## Role assignment (RP-06)

  @doc """
  Returns true when the user holds the owner role.
  """
  @spec owner?(User.t() | nil) :: boolean()
  def owner?(nil), do: false

  def owner?(%User{id: user_id}) do
    Repo.exists?(
      from ur in UserRole,
        join: r in Role,
        on: ur.role_id == r.id,
        where: ur.user_id == ^user_id and r.built_in and r.name == "owner"
    )
  end

  @doc """
  Returns the roles given to a user, highest rank first: what `user_roles` stores, without
  the implicit guest and member. An unverified user acts only with owner or administrator
  of these until they verify (`roles_of/1`).
  """
  @spec assigned_roles(User.t()) :: [Role.t()]
  def assigned_roles(%User{id: user_id}) do
    Repo.all(
      from r in Role,
        join: ur in UserRole,
        on: ur.role_id == r.id,
        where: ur.user_id == ^user_id,
        order_by: [asc: r.position, asc: r.name]
    )
  end

  @doc """
  Returns true when `admin` may give or remove `role`: guest and member are never given, and
  only an owner gives or removes the owner role (steward rule, 2026-10-19).
  """
  @spec assignable?(User.t(), Role.t()) :: boolean()
  def assignable?(%User{}, %Role{built_in: true, name: name}) when name in ~w(guest member),
    do: false

  def assignable?(%User{} = admin, %Role{built_in: true, name: "owner"}), do: owner?(admin)
  def assignable?(%User{}, %Role{}), do: true

  @doc """
  Gives a role to a user, as `admin`. Audited as `role.grant`. Giving a role the user
  already holds changes nothing.
  """
  @spec assign_role(User.t(), User.t(), Role.t()) ::
          {:ok, Role.t()} | {:error, :implicit_role | :owner_only}
  def assign_role(%User{} = admin, %User{} = user, %Role{} = role) do
    Repo.transact(fn ->
      with :ok <- check_assignable(admin, role), do: insert_assignment(admin, user, role)
    end)
  end

  @doc """
  Takes a role away from a user, as `admin`. Audited as `role.revoke`.

  Refused so nobody is locked out: the last owner keeps the owner role (`:last_owner`) and an
  administrator cannot remove their own administrator role (`:own_administrator`).
  """
  @spec unassign_role(User.t(), User.t(), Role.t()) ::
          {:ok, Role.t()}
          | {:error, :implicit_role | :owner_only | :last_owner | :own_administrator}
  def unassign_role(%User{} = admin, %User{} = user, %Role{} = role) do
    Repo.transact(fn ->
      with :ok <- check_assignable(admin, role),
           :ok <- check_not_own_administrator(admin, user, role),
           :ok <- check_not_last_owner(role) do
        delete_assignment(admin, user, role)
      end
    end)
  end

  defp check_assignable(admin, %Role{built_in: true, name: name} = role)
       when name in ~w(guest member owner) do
    cond do
      assignable?(admin, role) -> :ok
      name == "owner" -> {:error, :owner_only}
      true -> {:error, :implicit_role}
    end
  end

  defp check_assignable(_admin, %Role{}), do: :ok

  defp check_not_own_administrator(%User{id: id}, %User{id: id}, %Role{
         built_in: true,
         name: "administrator"
       }),
       do: {:error, :own_administrator}

  defp check_not_own_administrator(_admin, _user, _role), do: :ok

  defp check_not_last_owner(%Role{built_in: true, name: "owner"} = owner) do
    lock_owners()

    if Repo.aggregate(from(ur in UserRole, where: ur.role_id == ^owner.id), :count) > 1,
      do: :ok,
      else: {:error, :last_owner}
  end

  defp check_not_last_owner(%Role{}), do: :ok

  @doc """
  Returns `:ok`, or `{:error, :last_owner}` when the user is the server's only owner, who
  must never go away (AC-07). Locks the owner role like removing it does, so call it inside
  the transaction that removes the user.
  """
  @spec ensure_not_last_owner(User.t()) :: :ok | {:error, :last_owner}
  def ensure_not_last_owner(%User{} = user) do
    if owner?(user), do: check_not_last_owner(built_in_role!(:owner)), else: :ok
  end

  # Nothing changes, and nothing is audited, when the user already holds the role (or not).
  defp insert_assignment(admin, user, role) do
    case Repo.insert_all(UserRole, [%{user_id: user.id, role_id: role.id}], on_conflict: :nothing) do
      {0, _} -> {:ok, role}
      {1, _} -> audit_assignment(admin, "role.grant", nil, assignment(user, role), role)
    end
  end

  defp delete_assignment(admin, user, role) do
    case Repo.delete_all(
           from ur in UserRole, where: ur.user_id == ^user.id and ur.role_id == ^role.id
         ) do
      {0, _} -> {:ok, role}
      {1, _} -> audit_assignment(admin, "role.revoke", assignment(user, role), nil, role)
    end
  end

  defp assignment(user, role), do: %{"user" => user.username, "role" => role.name}

  defp audit_assignment(admin, change, before, after_, role) do
    with {:ok, _} <- Audit.record(admin, change, before, after_), do: {:ok, role}
  end

  # Two owners removing each other at once must not both see the other one left. NO KEY
  # UPDATE, so giving any role (a foreign key check on roles) is never blocked by it.
  defp lock_owners do
    Repo.one!(
      from r in Role,
        where: r.built_in and r.name == "owner",
        lock: "FOR NO KEY UPDATE",
        select: r.id
    )
  end

  @doc """
  Returns the colour a name is shown in (RP-06): the colour of the highest-ranked role that
  has one, or `nil`. Takes the roles from `roles_of/1` or `roles_of_users/1`.
  """
  @spec name_colour([Role.t()]) :: String.t() | nil
  def name_colour(roles) when is_list(roles) do
    case name_role(roles) do
      nil -> nil
      role -> role.colour
    end
  end

  @doc """
  Returns the role that sets the name colour (`name_colour/1`), or `nil` when no role has one.
  """
  @spec name_role([Role.t()]) :: Role.t() | nil
  def name_role(roles) when is_list(roles) do
    roles |> by_rank() |> Enum.find(& &1.colour)
  end

  @doc """
  Returns the role shown next to a name in conversations: the highest-ranked one that is
  "Visible next to name" (`show_next_to_name`; steward decision, 2026-10-23), or `nil`.
  """
  @spec shown_role([Role.t()]) :: Role.t() | nil
  def shown_role(roles) when is_list(roles) do
    roles |> by_rank() |> Enum.find(& &1.show_next_to_name)
  end

  defp by_rank(roles), do: Enum.sort_by(roles, &{&1.position, &1.name})

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
      %Ecto.Changeset{changes: changes} when changes == %{} ->
        {:ok, role}

      # Under the roles lock like every change to roles, so they always lock in the same order.
      changeset ->
        Repo.transact(fn ->
          lock_roles()
          save_role(admin, role, changeset)
        end)
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

  defp role_snapshot(role),
    do:
      Audit.snapshot(role, [
        :name,
        :colour,
        :show_next_to_name,
        :position,
        :mentionable,
        :mentions_below,
        :self_select
      ])

  ## Self-select roles (steward decision, 2026-10-23)

  @doc "The roles members may give themselves, highest rank first."
  @spec self_select_roles() :: [Role.t()]
  def self_select_roles do
    Repo.all(from r in Role, where: r.self_select and not r.built_in, order_by: [asc: r.position])
  end

  @doc """
  Sets which self-select roles the user holds: `role_ids` among `self_select_roles/0` are
  given, the other self-select roles taken away; their other roles never change. Each change
  is audited (`role.self_grant` / `role.self_revoke`, by the user).
  """
  @spec set_self_roles(User.t(), [String.t()]) :: {:ok, [Role.t()]}
  def set_self_roles(%User{} = user, role_ids) do
    Repo.transact(fn ->
      lock_roles()
      choices = self_select_roles()

      held =
        MapSet.new(
          Repo.all(from ur in UserRole, where: ur.user_id == ^user.id, select: ur.role_id)
        )

      for role <- choices,
          do: set_self_role(user, role, role.id in role_ids, MapSet.member?(held, role.id))

      {:ok, Enum.filter(choices, &(&1.id in role_ids))}
    end)
  end

  defp set_self_role(user, role, true = _wanted, false = _held) do
    Repo.insert_all(UserRole, [%{user_id: user.id, role_id: role.id}], on_conflict: :nothing)
    {:ok, _} = Audit.record(user, "role.self_grant", nil, assignment(user, role))
  end

  defp set_self_role(user, role, false = _wanted, true = _held) do
    Repo.delete_all(from ur in UserRole, where: ur.user_id == ^user.id and ur.role_id == ^role.id)
    {:ok, _} = Audit.record(user, "role.self_revoke", assignment(user, role), nil)
  end

  defp set_self_role(_user, _role, _wanted, _held), do: :ok

  ## Role mentions (TP-10, +role)

  @doc """
  A role's name as written after `+`: its slug ("Help desk" is `+help-desk`).
  """
  @spec role_slug(Role.t()) :: String.t()
  def role_slug(%Role{name: name}), do: Idejo.Forum.slugify(name, "role")

  @doc "The role a `+slug` names, for its page; never member or guest."
  @spec get_role_by_slug(String.t()) :: Role.t() | nil
  def get_role_by_slug(slug) when is_binary(slug) do
    from(r in Role, where: not (r.built_in and r.name in ~w(member guest)))
    |> Repo.all()
    |> Enum.find(&(role_slug(&1) == String.downcase(slug)))
  end

  @doc """
  The active members of a role, by display name, at most `limit`, with how many there are in
  all: `{users, count}`. For the role's page (`/r/{slug}`), which a `+role` links to.
  """
  @spec list_role_members(Role.t(), pos_integer()) :: {[User.t()], non_neg_integer()}
  def list_role_members(%Role{id: role_id}, limit \\ 100) do
    members =
      from u in User,
        join: ur in UserRole,
        on: ur.user_id == u.id and ur.role_id == ^role_id,
        where: u.status == "active"

    {Repo.all(from u in members, order_by: [asc: u.display_name, asc: u.id], limit: ^limit),
     Repo.aggregate(members, :count)}
  end

  @doc """
  The roles the user may notify with `+role` (TP-10; steward decision, 2026-10-22), highest
  rank first: every role that is `mentionable`, and every role ranked below one of the user's
  roles that has `mentions_below`. Owners and administrators may notify every role. Member
  and guest are never mentioned; visitors mention nothing.
  """
  @spec mentionable_roles(User.t() | nil) :: [Role.t()]
  def mentionable_roles(nil), do: []

  def mentionable_roles(%User{} = user) do
    candidates =
      Repo.all(
        from r in Role,
          where: not (r.built_in and r.name in ~w(member guest)),
          order_by: [asc: r.position]
      )

    # Server accounts post the administrators' automessages (steward decision, 2026-11-01).
    if user.status == "system" or administrator?(user) do
      candidates
    else
      # Lower position ranks higher; the highest-ranked role that mentions below decides.
      top =
        user
        |> roles_of()
        |> Enum.filter(& &1.mentions_below)
        |> Enum.map(& &1.position)
        |> Enum.min(fn -> nil end)

      Enum.filter(candidates, &(&1.mentionable or (top != nil and &1.position > top)))
    end
  end

  # Positions are rewritten as a whole; one change at a time.
  defp lock_roles, do: Repo.query!("LOCK TABLE roles IN SHARE ROW EXCLUSIVE MODE")

  ## Category rights (RP-04)

  @rights [:view, :start, :post, :moderate, :tag]

  @doc """
  The rights: `:view`, `:start` (topics), `:post`, `:moderate`, and `:tag` (edit a topic's
  tags, TP-19; allowed server-wide for the built-in moderator by default).
  """
  @spec rights() :: [atom()]
  def rights, do: CategoryPermission.rights()

  @doc """
  Returns true when the visitor or user has `right` in `category`.

  Owners and administrators always have every right. Otherwise each of the user's roles
  (`roles_of/1`) gets the category's own setting for that role, or, when unset there, the
  role's server-wide setting; a deny on the category overrides the server-wide allow for that
  role. Across roles, **allow wins**: one role allowing is enough (RP-06).

  No category (`nil`: a private conversation's, steward decision, 2026-10-27) gives nobody
  any right, owners and administrators included: only its participants read and write there
  (`Idejo.Conversations`), so a call that skips them never opens one.
  """
  @spec can?(User.t() | nil, atom(), Category.t() | nil) :: boolean()
  def can?(_user, right, nil) when right in @rights, do: false

  def can?(user, right, %Category{id: category_id})
      when right in @rights do
    from(c in Category, where: c.id == ^category_id)
    |> where_allowed(user, right)
    |> Repo.exists?()
  end

  @doc """
  The users, among `users`, who have `right` in `category`: the same rule as `can?/3`, in a
  few queries whatever their number (a new message checks every follower of its topic,
  NO-01). Users who act with the same roles get the same answer, so the rule is asked once
  per set of roles.
  """
  @spec filter_allowed([User.t()], atom(), Category.t() | nil) :: [User.t()]
  def filter_allowed(_users, right, nil) when right in @rights, do: []
  def filter_allowed([], right, _category) when right in @rights, do: []

  def filter_allowed(users, right, %Category{id: category_id}) when right in @rights do
    roles = roles_of_users(users)
    category = from(c in Category, where: c.id == ^category_id)
    # Sorted and without repeats (roles_of_users/1), so the ids name the set.
    role_set = fn held -> Enum.map(held, & &1.id) end

    answers =
      roles
      |> Map.values()
      |> Enum.uniq_by(role_set)
      |> Map.new(&{role_set.(&1), category |> where_roles(&1, [right]) |> Repo.exists?()})

    Enum.filter(users, &Map.fetch!(answers, role_set.(roles[&1.id])))
  end

  @doc """
  Narrows a query on categories to those where the visitor or user has `right`, in the
  database: lists and search filter this way, never after loading. Same rule as `can?/3`.
  A list of rights needs them all, with one look at the user's roles.
  """
  @spec where_allowed(Ecto.Queryable.t(), User.t() | nil, atom() | [atom(), ...]) ::
          Ecto.Query.t()
  def where_allowed(query, user, right) when right in @rights,
    do: where_roles(query, roles_of(user), [right])

  def where_allowed(query, user, [_ | _] = rights) do
    true = Enum.all?(rights, &(&1 in @rights))
    where_roles(query, roles_of(user), rights)
  end

  # The administrator check comes from the roles already loaded (`administrator?/1` asks the
  # database): owners and administrators have every right.
  defp where_roles(query, roles, rights) do
    query = from(c in query, as: :category)

    if all_rights?(roles) do
      query
    else
      role_ids = Enum.map(roles, & &1.id)
      Enum.reduce(rights, query, &where_role_allows(&2, role_ids, Atom.to_string(&1)))
    end
  end

  defp where_role_allows(query, role_ids, right) do
    from c in query,
      where:
        exists(
          from r in Role,
            left_join: own in CategoryPermission,
            on:
              own.category_id == parent_as(:category).id and own.role_id == r.id and
                own.right == ^right,
            left_join: server in CategoryPermission,
            on: is_nil(server.category_id) and server.role_id == r.id and server.right == ^right,
            where: r.id in ^role_ids and coalesce(own.effect, server.effect) == "allow"
        )
  end

  # The same as `administrator?/1`, from roles already loaded (`roles_of/1`).
  defp all_rights?(roles), do: Enum.any?(roles, &(&1.built_in and &1.name in @all_rights))

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
      when right in @rights and effect in [:allow, :deny, :unset] do
    result =
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
          {:ok, {effect, before != effect}}
        end
      end)

    case result do
      {:ok, {effect, changed?}} ->
        if changed?, do: Phoenix.PubSub.broadcast(Idejo.PubSub, @grid_topic, :permissions_changed)
        {:ok, effect}

      error ->
        error
    end
  end

  @doc """
  Subscribes the caller to changes of the permission grid: `:permissions_changed` arrives
  after any setting changes. Open pages that were allowed at mount, such as a live topic
  (TP-04), check again then (steward decision, 2026-10-19).
  """
  @spec subscribe_permissions() :: :ok | {:error, term()}
  def subscribe_permissions, do: Phoenix.PubSub.subscribe(Idejo.PubSub, @grid_topic)

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
