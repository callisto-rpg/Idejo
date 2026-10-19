# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminRolesLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Access.Role

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp role!(name), do: Idejo.Repo.get_by!(Role, name: name)
  defp names, do: Enum.map(Access.list_roles(), & &1.name)

  @tag req: "RP-02"
  test "RP-02 only administrators open the role editor" do
    conn =
      build_conn() |> log_in_user(user_with_role_fixture(:moderator)) |> get(~p"/admin/roles")

    assert redirected_to(conn) == ~p"/"
  end

  @tag req: "RP-02"
  test "RP-02 lists the roles in rank order with translated built-in names", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin/roles")

    positions =
      for name <- ~w(Owner Administrator Moderator Member Guest), do: :binary.match(html, name)

    assert positions == Enum.sort(positions)
  end

  @tag req: "RP-02"
  test "RP-02 creating a role from the form", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/roles")

    html =
      lv
      |> form("#new-role-form", role: %{name: "Team", colour: "#3366ff"})
      |> render_submit()

    assert html =~ "Role “Team” created."
    team = role!("Team")
    assert lv |> element("#role-#{team.id}") |> render() =~ ~s(fill="#3366ff")
  end

  @tag req: "RP-02"
  test "RP-02 form errors are shown", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/roles")

    assert lv |> form("#new-role-form", role: %{name: "member"}) |> render_submit() =~
             "is already used by another role"
  end

  @tag req: "RP-02"
  test "RP-02 renaming, moving and deleting a role", %{conn: conn, admin: admin} do
    {:ok, team} = Access.create_role(admin, %{"name" => "Team"})
    {:ok, lv, _html} = live(conn, ~p"/admin/roles")

    lv |> element("#role-#{team.id} button", "Edit") |> render_click()

    lv
    |> form("#edit-role-#{team.id}", edit: %{name: "Crew", colour: ""})
    |> render_submit()

    assert role!("Crew").id == team.id

    lv |> element(~s(#role-#{team.id} button[phx-value-direction="up"])) |> render_click()
    assert names() == ~w(owner administrator moderator Crew member guest)

    assert lv |> element("#role-#{team.id} button", "Delete") |> render_click() =~
             "Role “Crew” deleted."

    refute Idejo.Repo.get(Role, team.id)
  end

  @tag req: "RP-02"
  test "RP-02 fixed roles have no move or delete buttons", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/roles")

    for name <- ~w(owner administrator guest) do
      html = lv |> element("#role-#{role!(name).id}") |> render()
      refute html =~ "phx-value-direction"
      refute html =~ "Delete"
    end

    refute lv |> element("#role-#{role!("member").id}") |> render() =~ "Delete"
  end
end
