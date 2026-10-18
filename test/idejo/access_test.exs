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
    test "RP-01 verifying the email address grants member" do
      user = user_fixture()
      assert names(Access.roles_of(user)) == ["member"]
    end

    @tag req: "RP-01"
    test "RP-01 roles are listed highest rank first" do
      user = user_fixture()
      :ok = Access.grant_role(user, Access.built_in_role!(:moderator))

      assert names(Access.roles_of(user)) == ["moderator", "member"]
    end
  end

  describe "grant_role/2" do
    @tag req: "RP-01"
    test "RP-01 granting a role twice keeps one" do
      user = user_fixture()
      member = Access.built_in_role!(:member)

      assert :ok = Access.grant_role(user, member)
      assert names(Access.roles_of(user)) == ["member"]
    end

    @tag req: "RP-01"
    test "RP-01 guest is never held, only acted as" do
      user = user_fixture()

      assert {:error, :guest_is_implicit} =
               Access.grant_role(user, Access.built_in_role!(:guest))

      assert names(Access.roles_of(user)) == ["member"]
    end
  end
end
