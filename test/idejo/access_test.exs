# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccessTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Access.Role

  defp names(roles), do: Enum.map(roles, & &1.name)

  describe "built-in roles" do
    @tag req: "RP-01"
    test "RP-01 owner, administrator, moderator, member and guest are always present, in rank order" do
      roles = Access.list_roles()

      assert names(roles) == ~w(owner administrator moderator member guest)
      assert Enum.all?(roles, & &1.built_in)
    end

    @tag req: "RP-01"
    test "RP-01 built-in roles cannot be deleted" do
      role = Access.built_in_role!(:moderator)

      assert_raise Postgrex.Error, ~r/cannot be deleted/, fn -> Repo.delete(role) end
      assert Repo.reload(role)
    end

    @tag req: "RP-01"
    test "RP-01 built-in roles cannot be renamed or made custom" do
      role = Access.built_in_role!(:member)

      assert_raise Postgrex.Error, ~r/cannot be renamed/, fn ->
        role |> Ecto.Changeset.change(name: "people") |> Repo.update()
      end

      assert_raise Postgrex.Error, ~r/cannot be renamed/, fn ->
        role |> Ecto.Changeset.change(built_in: false) |> Repo.update()
      end

      assert Repo.reload(role).name == "member"
    end

    @tag req: "RP-01"
    test "RP-01 a built-in role's colour and position can still change" do
      role = Access.built_in_role!(:moderator)

      assert {:ok, role} =
               role |> Ecto.Changeset.change(colour: "#3366ff", position: 7) |> Repo.update()

      assert role.colour == "#3366ff"
    end

    @tag req: "RP-01"
    test "RP-01 only built-in roles are protected" do
      custom = Repo.insert!(%Role{name: "team", position: 5})
      assert {:ok, _} = Repo.delete(custom)
    end

    @tag req: "RP-01"
    test "RP-01 built_in_role! rejects names that are not built in" do
      assert_raise MatchError, fn -> Access.built_in_role!(:team) end
    end
  end

  describe "roles_of/1" do
    @tag req: "RP-01"
    test "RP-01 a visitor without an account acts as guest" do
      assert names(Access.roles_of(nil)) == ["guest"]
    end

    @tag req: "RP-01"
    test "RP-01 a user who has not verified their email acts as guest" do
      user = unconfirmed_user_fixture()
      assert names(Access.roles_of(user)) == ["guest"]
    end

    @tag req: "RP-01"
    test "RP-01 every verified user holds member" do
      user = user_fixture()
      assert names(Access.roles_of(user)) == ["member"]
    end

    @tag req: "RP-01"
    test "RP-01 a verified user keeps member alongside other roles, highest rank first" do
      user = user_fixture()
      :ok = Access.grant_role(user, Access.built_in_role!(:moderator))
      :ok = Access.grant_role(user, Repo.insert!(%Role{name: "team", position: 10}))

      assert names(Access.roles_of(user)) == ["moderator", "member", "team"]
    end

    @tag req: "RP-01"
    test "RP-01 roles held by other users are not mixed in" do
      user = user_fixture()
      other = user_fixture()
      :ok = Access.grant_role(other, Access.built_in_role!(:administrator))

      assert names(Access.roles_of(user)) == ["member"]
    end

    @tag req: "RP-01"
    test "RP-01 guest and member are implicit, never stored" do
      user_fixture()
      assert Repo.aggregate(Idejo.Access.UserRole, :count) == 0
    end

    @tag req: "RP-01"
    test "RP-01 nobody is ever without a role" do
      for subject <- [nil, unconfirmed_user_fixture(), user_fixture()] do
        assert [_ | _] = Access.roles_of(subject)
      end
    end
  end

  describe "grant_role/2" do
    @tag req: "RP-01"
    test "RP-01 granting a role twice keeps one" do
      user = user_fixture()
      moderator = Access.built_in_role!(:moderator)

      assert :ok = Access.grant_role(user, moderator)
      assert :ok = Access.grant_role(user, moderator)
      assert names(Access.roles_of(user)) == ["moderator", "member"]
    end

    @tag req: "RP-01"
    test "RP-01 guest and member cannot be granted" do
      user = user_fixture()

      for name <- [:guest, :member] do
        assert {:error, :implicit_role} = Access.grant_role(user, Access.built_in_role!(name))
      end

      assert Repo.aggregate(Idejo.Access.UserRole, :count) == 0
    end
  end
end
