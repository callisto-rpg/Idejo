# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccessRolesEditorTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Access.Role
  alias Idejo.Audit

  setup do
    %{admin: user_with_role_fixture(:administrator)}
  end

  defp names, do: Enum.map(Access.list_roles(), & &1.name)
  defp role!(name), do: Repo.get_by!(Role, name: name)

  describe "create_role/2" do
    @tag req: "RP-02"
    test "RP-02 a new role has a name and colour and ranks just above guest", %{admin: admin} do
      assert {:ok, team} = Access.create_role(admin, %{"name" => " Team ", "colour" => "#3366FF"})
      assert {:ok, _} = Access.create_role(admin, %{"name" => "Pilots"})

      assert team.name == "Team"
      assert team.colour == "#3366ff"
      refute team.built_in
      assert names() == ~w(owner administrator moderator member Team Pilots guest)
      assert Enum.map(Access.list_roles(), & &1.position) == Enum.to_list(0..6)
    end

    @tag req: "RP-02"
    test "RP-02 an unlimited number of roles can be created", %{admin: admin} do
      for n <- 1..30, do: {:ok, _} = Access.create_role(admin, %{"name" => "Role #{n}"})
      assert length(Access.list_roles()) == 35
      assert List.last(names()) == "guest"
    end

    @tag req: "RP-02"
    test "RP-02 names are required, short and unique ignoring case", %{admin: admin} do
      {:ok, _} = Access.create_role(admin, %{"name" => "Team"})

      for {name, error} <- [
            {"", "can't be blank"},
            {String.duplicate("x", 41), "should be at most 40 character(s)"},
            {"team", "is already used by another role"},
            {"Member", "is already used by another role"}
          ] do
        assert {:error, changeset} = Access.create_role(admin, %{"name" => name})
        assert error in errors_on(changeset).name
      end
    end

    @tag req: "RP-02"
    test "RP-02 a colour must be #rrggbb", %{admin: admin} do
      for bad <- ["red", "#12345", "#gggggg", "3366ff"] do
        assert {:error, changeset} = Access.create_role(admin, %{"name" => "T", "colour" => bad})
        assert "must look like #3366ff" in errors_on(changeset).colour
      end
    end

    @tag req: "RP-02"
    test "RP-02 creating a role is audited", %{admin: admin} do
      {:ok, _} = Access.create_role(admin, %{"name" => "Team", "colour" => "#3366ff"})

      assert [%{change: "role.create", admin_id: admin_id, before: nil, after: after_}] =
               Audit.list_entries()

      assert admin_id == admin.id

      assert after_ == %{
               "name" => "Team",
               "colour" => "#3366ff",
               "show_next_to_name" => true,
               "position" => 4,
               "mentionable" => false,
               "mentions_below" => false,
               "self_select" => false
             }
    end
  end

  describe "update_role/3" do
    @tag req: "RP-02"
    test "RP-02 a custom role is renamed and recoloured, audited", %{admin: admin} do
      {:ok, team} = Access.create_role(admin, %{"name" => "Team"})

      assert {:ok, crew} =
               Access.update_role(admin, team, %{"name" => "Crew", "colour" => "#00aa00"})

      assert {crew.name, crew.colour} == {"Crew", "#00aa00"}
      assert [%{change: "role.update", before: before, after: after_} | _] = Audit.list_entries()
      assert {before["name"], after_["name"]} == {"Team", "Crew"}
    end

    @tag req: "RP-02"
    test "RP-02 a built-in role keeps its name but its colour can change", %{admin: admin} do
      moderator = Access.built_in_role!(:moderator)

      assert {:ok, moderator} =
               Access.update_role(admin, moderator, %{"name" => "Mods", "colour" => "#aa0000"})

      assert {moderator.name, moderator.colour} == {"moderator", "#aa0000"}
    end

    @tag req: "RP-02"
    test "RP-02 clearing the colour removes it; unchanged values write nothing", %{admin: admin} do
      {:ok, team} = Access.create_role(admin, %{"name" => "Team", "colour" => "#3366ff"})
      {:ok, team} = Access.update_role(admin, team, %{"colour" => ""})
      assert team.colour == nil

      count = length(Audit.list_entries())
      assert {:ok, _} = Access.update_role(admin, team, %{"name" => "Team"})
      assert length(Audit.list_entries()) == count
    end
  end

  describe "move_role/3" do
    setup %{admin: admin} do
      {:ok, team} = Access.create_role(admin, %{"name" => "Team"})
      %{team: team}
    end

    @tag req: "RP-02"
    test "RP-02 roles move up and down in rank, audited", %{admin: admin, team: team} do
      assert {:ok, _} = Access.move_role(admin, team, :up)
      assert names() == ~w(owner administrator moderator Team member guest)

      assert {:ok, _} = Access.move_role(admin, team, :up)
      assert names() == ~w(owner administrator Team moderator member guest)

      assert {:ok, _} = Access.move_role(admin, role!("moderator"), :down)
      assert names() == ~w(owner administrator Team member moderator guest)

      assert [
               %{
                 change: "role.reorder",
                 before: %{"order" => before},
                 after: %{"order" => after_}
               }
               | _
             ] =
               Audit.list_entries()

      assert before == ~w(owner administrator Team moderator member guest)
      assert after_ == ~w(owner administrator Team member moderator guest)
    end

    @tag req: "RP-02"
    test "RP-02 owner and administrator stay on top and guest stays last", %{
      admin: admin,
      team: team
    } do
      {:ok, _} = Access.move_role(admin, team, :up)
      {:ok, _} = Access.move_role(admin, team, :up)

      assert {:error, :fixed_rank} = Access.move_role(admin, role!("Team"), :up)
      assert {:error, :fixed_rank} = Access.move_role(admin, role!("owner"), :down)
      assert {:error, :fixed_rank} = Access.move_role(admin, role!("administrator"), :up)
      assert {:error, :fixed_rank} = Access.move_role(admin, role!("guest"), :up)
      assert {:error, :fixed_rank} = Access.move_role(admin, role!("member"), :down)

      assert names() == ~w(owner administrator Team moderator member guest)
      refute Access.movable?(role!("owner"))
      refute Access.movable?(role!("guest"))
      assert Access.movable?(role!("member"))
    end
  end

  describe "delete_role/2" do
    @tag req: "RP-02"
    test "RP-02 deleting a custom role removes it from its members and closes the gap", %{
      admin: admin
    } do
      {:ok, team} = Access.create_role(admin, %{"name" => "Team"})
      {:ok, _} = Access.create_role(admin, %{"name" => "Pilots"})
      user = user_fixture()
      :ok = Access.grant_role(user, team)
      assert "Team" in Enum.map(Access.roles_of(user), & &1.name)

      assert {:ok, _} = Access.delete_role(admin, team)

      assert names() == ~w(owner administrator moderator member Pilots guest)
      assert Enum.map(Access.list_roles(), & &1.position) == Enum.to_list(0..5)
      refute "Team" in Enum.map(Access.roles_of(user), & &1.name)

      assert [%{change: "role.delete", before: %{"name" => "Team"}, after: nil} | _] =
               Audit.list_entries()
    end

    @tag req: "RP-02"
    test "RP-02 built-in roles cannot be deleted", %{admin: admin} do
      for name <- Role.built_in_names() do
        assert {:error, :built_in} = Access.delete_role(admin, role!(name))
      end

      assert length(Access.list_roles()) == 5
    end
  end

  @tag req: "RP-02"
  test "RP-02 holder counts show how many users hold each role", %{admin: admin} do
    {:ok, team} = Access.create_role(admin, %{"name" => "Team"})
    for _ <- 1..3, do: :ok = Access.grant_role(user_fixture(), team)

    assert Access.holder_counts()[team.id] == 3
  end
end
