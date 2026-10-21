# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccessRoleAssignmentTest do
  # Not async: it moves and recolours the built-in roles, rows every test shares.
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit
  alias Idejo.Forum

  setup do
    owner = user_with_role_fixture(:owner)
    admin = user_with_role_fixture(:administrator)
    %{owner: owner, admin: admin}
  end

  defp role(name), do: Access.built_in_role!(name)
  defp names(user), do: Enum.map(Access.roles_of(user), & &1.name)

  describe "giving and removing roles" do
    @tag req: "RP-06"
    test "RP-06 users hold several roles", %{admin: admin} do
      {:ok, team} = Access.create_role(admin, %{"name" => unique_role_name("Team")})
      user = user_fixture()

      assert {:ok, _} = Access.assign_role(admin, user, role(:moderator))
      assert {:ok, _} = Access.assign_role(admin, user, team)

      assert names(user) == ["moderator", "member", team.name]
      assert Enum.map(Access.assigned_roles(user), & &1.name) == ["moderator", team.name]
    end

    @tag req: "RP-06"
    test "RP-06 giving and removing are audited once", %{admin: admin} do
      user = user_fixture()

      {:ok, _} = Access.assign_role(admin, user, role(:moderator))
      {:ok, _} = Access.assign_role(admin, user, role(:moderator))
      {:ok, _} = Access.unassign_role(admin, user, role(:moderator))
      {:ok, _} = Access.unassign_role(admin, user, role(:moderator))

      assert [revoke, grant] = Audit.list_entries(limit: 2)
      assert grant.change == "role.grant"
      assert grant.after == %{"user" => user.username, "role" => "moderator"}
      assert revoke.change == "role.revoke"
      assert revoke.before == %{"user" => user.username, "role" => "moderator"}
      assert revoke.admin_id == admin.id
      assert length(Audit.list_entries()) == 2
    end

    @tag req: "RP-06"
    test "RP-06 guest and member are never given or removed", %{admin: admin} do
      user = user_fixture()

      for name <- [:guest, :member] do
        assert Access.assign_role(admin, user, role(name)) == {:error, :implicit_role}
        assert Access.unassign_role(admin, user, role(name)) == {:error, :implicit_role}
      end
    end

    @tag req: "RP-06"
    test "RP-06 removing a role takes its rights away", %{admin: admin} do
      {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
      user = user_fixture()
      {:ok, _} = Access.assign_role(admin, user, role(:moderator))
      assert Access.can?(user, :moderate, general)

      {:ok, _} = Access.unassign_role(admin, user, role(:moderator))
      refute Access.can?(user, :moderate, general)
    end
  end

  describe "never locked out" do
    @tag req: "RP-06"
    test "RP-06 only owners give or remove the owner role", %{owner: owner, admin: admin} do
      user = user_fixture()

      assert Access.assign_role(admin, user, role(:owner)) == {:error, :owner_only}
      refute Access.owner?(user)

      assert {:ok, _} = Access.assign_role(owner, user, role(:owner))
      assert Access.owner?(user)

      assert Access.unassign_role(admin, user, role(:owner)) == {:error, :owner_only}
      assert {:ok, _} = Access.unassign_role(owner, user, role(:owner))
      refute Access.owner?(user)
    end

    @tag req: "RP-06"
    test "RP-06 the last owner keeps the owner role", %{owner: owner} do
      assert Access.unassign_role(owner, owner, role(:owner)) == {:error, :last_owner}
      assert Access.owner?(owner)

      second = user_fixture()
      {:ok, _} = Access.assign_role(owner, second, role(:owner))
      assert {:ok, _} = Access.unassign_role(owner, owner, role(:owner))
      assert Access.unassign_role(second, second, role(:owner)) == {:error, :last_owner}
    end

    @tag req: "RP-06"
    test "RP-06 an administrator cannot remove their own administrator role", %{
      owner: owner,
      admin: admin
    } do
      assert Access.unassign_role(admin, admin, role(:administrator)) ==
               {:error, :own_administrator}

      assert Access.administrator?(admin)

      other = user_with_role_fixture(:administrator)
      assert {:ok, _} = Access.unassign_role(admin, other, role(:administrator))
      refute Access.administrator?(other)

      assert {:ok, _} = Access.unassign_role(owner, admin, role(:administrator))
      refute Access.administrator?(admin)
    end
  end

  describe "name colour" do
    @tag req: "RP-06"
    test "RP-06 the highest-ranked role with a colour sets the name colour", %{admin: admin} do
      {:ok, _} = Access.update_role(admin, role(:moderator), %{"colour" => "#2255aa"})

      {:ok, team} =
        Access.create_role(admin, %{"name" => unique_role_name("Team"), "colour" => "#aa2255"})

      {:ok, plain} = Access.create_role(admin, %{"name" => unique_role_name("Plain")})
      {:ok, _} = Access.move_role(admin, plain, :up)
      {:ok, _} = Access.move_role(admin, plain, :up)
      {:ok, _} = Access.move_role(admin, plain, :up)

      user = user_fixture()
      assert Access.name_colour(Access.roles_of(user)) == nil

      {:ok, _} = Access.assign_role(admin, user, team)
      assert Access.name_colour(Access.roles_of(user)) == "#aa2255"

      {:ok, _} = Access.assign_role(admin, user, role(:moderator))
      assert Access.name_colour(Access.roles_of(user)) == "#2255aa"

      # Plain now ranks above moderator but has no colour, so it does not count.
      {:ok, _} = Access.assign_role(admin, user, Repo.reload!(plain))
      assert hd(Access.roles_of(user)).name == plain.name
      assert Access.name_colour(Access.roles_of(user)) == "#2255aa"
    end
  end
end
