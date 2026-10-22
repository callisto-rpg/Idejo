# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminPermissionsLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit
  alias Idejo.Forum

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    %{conn: log_in_user(conn, admin), admin: admin, general: general}
  end

  defp role(name), do: Access.built_in_role!(name)

  defp set(lv, role, right, effect) do
    lv
    |> form("#permission-#{role.id}-#{right}", %{effect: effect})
    |> render_change()
  end

  @tag req: "RP-05"
  test "RP-05 only administrators open the permission grid" do
    conn =
      build_conn()
      |> log_in_user(user_with_role_fixture(:moderator))
      |> get(~p"/admin/permissions")

    assert redirected_to(conn) == ~p"/"
  end

  @tag req: "RP-05"
  test "RP-05 the server-wide grid shows the seeded defaults", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/permissions")

    member = role(:member)
    assert has_element?(lv, "#permission-#{member.id}-post option[selected][value=allow]")
    assert has_element?(lv, "#permission-#{member.id}-moderate option[selected][value=unset]")
    # Server-wide a right is allowed or not: no deny to choose.
    refute has_element?(lv, "#permission-#{member.id}-post option[value=deny]")
  end

  @tag req: "RP-05"
  test "RP-05 owner and administrator rows take no settings", %{conn: conn, general: general} do
    {:ok, lv, _html} = live(conn, ~p"/admin/permissions/#{general.slug}")

    for name <- [:owner, :administrator] do
      role = role(name)
      assert lv |> element("#role-#{role.id}") |> render() =~ "Always"
      refute has_element?(lv, "#role-#{role.id} select")
    end
  end

  @tag req: "RP-05"
  test "RP-05 denying a right on a category overrides the server-wide allow", %{
    conn: conn,
    admin: admin,
    general: general
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/permissions/#{general.slug}")
    member = role(:member)
    user = user_fixture()

    assert has_element?(
             lv,
             "#permission-#{member.id}-post option[selected][value=unset]",
             "Server-wide (allowed)"
           )

    assert Access.can?(user, :post, general)

    set(lv, member, :post, "deny")

    refute Access.can?(user, :post, general)
    assert Access.permissions(general) == %{{member.id, :post} => :deny}
    assert has_element?(lv, "#permission-#{member.id}-post option[selected][value=deny]")

    assert [%{change: "permission.update", admin_id: admin_id, after: %{"effect" => "deny"}} | _] =
             Audit.list_entries()

    assert admin_id == admin.id

    set(lv, member, :post, "unset")
    assert Access.permissions(general) == %{}
    assert Access.can?(user, :post, general)
  end

  @tag req: "RP-05"
  test "RP-05 a server-wide allow applies to every category", %{
    conn: conn,
    general: general
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/permissions")
    guest = role(:guest)

    refute Access.can?(nil, :post, general)
    set(lv, guest, :post, "allow")
    assert Access.can?(nil, :post, general)
    assert Access.permissions(:server)[{guest.id, :post}] == :allow
  end

  @tag req: "RP-05"
  test "RP-05 a server-wide deny sent by hand is refused", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/permissions")
    member = role(:member)

    html =
      render_change(lv, "set", %{
        "role" => member.id,
        "right" => "post",
        "effect" => "deny"
      })

    assert html =~ "This setting cannot be changed."
    assert Access.permissions(:server)[{member.id, :post}] == :allow
  end

  @tag req: "RP-05"
  test "RP-05 the owner and administrator rights cannot be changed by hand", %{
    conn: conn,
    general: general
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/permissions/#{general.slug}")

    html =
      render_change(lv, "set", %{
        "role" => role(:administrator).id,
        "right" => "view",
        "effect" => "deny"
      })

    assert html =~ "This setting cannot be changed."
    assert Access.permissions(general) == %{}
  end

  @tag req: "RP-05"
  test "RP-05 the grid lists custom roles and switches between categories", %{
    conn: conn,
    admin: admin,
    general: general
  } do
    {:ok, team} = Access.create_role(admin, %{"name" => unique_role_name("Team")})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
    {:ok, lv, _html} = live(conn, ~p"/admin/permissions/#{general.slug}")

    assert has_element?(lv, "#role-#{team.id}", "Team")

    lv |> element(~s(nav[aria-label="Where the settings apply"] a), "Help") |> render_click()
    assert_patch(lv, ~p"/admin/permissions/#{help.slug}")

    set(lv, team, :view, "allow")
    assert Access.permissions(help) == %{{team.id, :view} => :allow}
    assert Access.permissions(general) == %{}
  end

  @tag req: "RP-05"
  test "RP-05 an unknown category goes back to the server-wide grid", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/permissions"}}} =
             live(conn, ~p"/admin/permissions/nowhere")
  end
end
