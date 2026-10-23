# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminUserRolesLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp role(name), do: Access.built_in_role!(name)

  @tag req: "RP-06"
  test "RP-06 an administrator gives and removes a role", %{conn: conn} do
    user = user_fixture()
    moderator = role(:moderator)
    {:ok, lv, html} = live(conn, ~p"/admin/users/#{user.id}")
    assert html =~ "No roles given."

    html =
      lv |> form("#assign-role-form", assign: %{role_id: moderator.id}) |> render_submit()

    assert html =~ "Role “Moderator” given."
    assert has_element?(lv, "#assigned-#{moderator.id}", "Moderator")
    assert Enum.map(Access.assigned_roles(user), & &1.name) == ["moderator"]
    # Already held, so it is no longer offered.
    refute has_element?(lv, "#assign-role-form option[value='#{moderator.id}']")

    html = lv |> element("#assigned-#{moderator.id} button", "Remove") |> render_click()
    assert html =~ "Role “Moderator” removed."
    assert Access.assigned_roles(user) == []
  end

  @tag req: "RP-06"
  test "RP-06 guest, member and owner are not offered to an administrator", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/users/#{user_fixture().id}")

    for name <- [:guest, :member, :owner] do
      refute has_element?(lv, "#assign-role-form option[value='#{role(name).id}']")
    end

    assert has_element?(lv, "#assign-role-form option[value='#{role(:administrator).id}']")
  end

  @tag req: "RP-06"
  test "RP-06 an owner can give the owner role" do
    owner = user_with_role_fixture(:owner)
    user = user_fixture()
    {:ok, lv, _html} = live(log_in_user(build_conn(), owner), ~p"/admin/users/#{user.id}")

    lv |> form("#assign-role-form", assign: %{role_id: role(:owner).id}) |> render_submit()
    assert Access.owner?(user)
  end

  @tag req: "RP-06"
  test "RP-06 an administrator has no button to remove their own administrator role", %{
    conn: conn,
    admin: admin
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/users/#{admin.id}")
    administrator = role(:administrator)

    assert has_element?(lv, "#assigned-#{administrator.id}")
    refute has_element?(lv, "#assigned-#{administrator.id} button")

    # Sent by hand, it is refused.
    assert render_click(lv, "unassign", %{"id" => administrator.id}) =~
             "You cannot remove your own administrator role."

    assert Access.administrator?(admin)
  end

  @tag req: "RP-06"
  test "RP-06 the last owner's role cannot be removed" do
    owner = user_with_role_fixture(:owner)
    {:ok, lv, _html} = live(log_in_user(build_conn(), owner), ~p"/admin/users/#{owner.id}")

    assert lv |> element("#assigned-#{role(:owner).id} button", "Remove") |> render_click() =~
             "The server must keep at least one owner."

    assert Access.owner?(owner)
  end

  @tag req: "RP-06"
  test "RP-06 a removed administrator's open pages are disconnected", %{conn: conn} do
    other = user_with_role_fixture(:administrator)
    socket_id = other_session_socket_id(other)
    IdejoWeb.Endpoint.subscribe(IdejoWeb.UserAuth.live_socket_id(socket_id))
    {:ok, _} = Access.assign_role(other, other, role(:moderator))
    {:ok, lv, _html} = live(conn, ~p"/admin/users/#{other.id}")

    # Removing a role that leaves them administrator does not disconnect them.
    lv |> element("#assigned-#{role(:moderator).id} button", "Remove") |> render_click()
    refute_received %Phoenix.Socket.Broadcast{event: "disconnect"}

    lv |> element("#assigned-#{role(:administrator).id} button", "Remove") |> render_click()
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    refute Access.administrator?(other)
  end

  defp other_session_socket_id(user) do
    signed_in = log_in_user(build_conn(), user)
    Accounts.session_socket_id(Plug.Conn.get_session(signed_in, :user_token))
  end

  @tag req: "RP-06"
  test "RP-06 the users list shows each name's colour", %{conn: conn, admin: admin} do
    {:ok, team} = Access.create_role(admin, %{"name" => "Team", "colour" => "#aa2255"})
    user = user_fixture()
    {:ok, _} = Access.assign_role(admin, user, team)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")
    assert has_element?(lv, "#user-#{user.id} .name-colour[data-role-colour='#aa2255']")
  end
end
