# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.WelcomeTest do
  # Writes server-wide settings (About, Rules), which every test shares.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Audit
  alias Idejo.Repo
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)

    {:ok, _} =
      Settings.update_settings(admin, %{
        "server_about" => "A place for **gardeners**.",
        "server_rules" => "1. Be kind\n2. No spam"
      })

    {:ok, growers} =
      Access.create_role(admin, %{"name" => unique_role_name("Growers"), "self_select" => "true"})

    {:ok, cooks} =
      Access.create_role(admin, %{"name" => unique_role_name("Cooks"), "self_select" => "true"})

    {:ok, staff} = Access.create_role(admin, %{"name" => unique_role_name("Staff")})
    %{admin: admin, growers: growers, cooks: cooks, staff: staff}
  end

  test "custom roles may be self-select; members set only those, audited", %{
    admin: admin,
    growers: growers,
    cooks: cooks,
    staff: staff
  } do
    {:ok, moderator} =
      Access.update_role(admin, Access.built_in_role!(:moderator), %{"self_select" => "true"})

    refute moderator.self_select
    assert growers.id in Enum.map(Access.self_select_roles(), & &1.id)
    refute staff.id in Enum.map(Access.self_select_roles(), & &1.id)

    user = user_fixture()
    :ok = Access.grant_role(user, staff)

    {:ok, _} = Access.set_self_roles(user, [growers.id, staff.id])
    ids = Enum.map(Access.roles_of(user), & &1.id)
    assert growers.id in ids and staff.id in ids

    {:ok, _} = Access.set_self_roles(user, [cooks.id])
    ids = Enum.map(Access.roles_of(user), & &1.id)
    assert cooks.id in ids and staff.id in ids
    refute growers.id in ids

    changes = Enum.map(Audit.list_entries(), & &1.change)
    assert "role.self_grant" in changes and "role.self_revoke" in changes
  end

  test "a new member sees the welcome card once; continuing saves their roles", %{
    growers: growers
  } do
    newcomer = user_fixture(%{welcome: true})
    assert newcomer.welcomed_at == nil
    conn = log_in_user(build_conn(), newcomer)

    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(id="welcome-card")
    assert html =~ "<strong>gardeners</strong>"
    assert html =~ "No spam"
    assert html =~ growers.name

    conn = post(conn, ~p"/welcome", %{"role_ids" => ["", growers.id]})
    assert redirected_to(conn) == ~p"/"
    assert Repo.reload!(newcomer).welcomed_at
    assert growers.id in Enum.map(Access.roles_of(newcomer), & &1.id)

    refute build_conn() |> log_in_user(Repo.reload!(newcomer)) |> get(~p"/") |> html_response(200) =~
             ~s(id="welcome-card")

    # Members who joined before, and the owner from the wizard, never see it.
    refute build_conn() |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200) =~
             ~s(id="welcome-card")

    {:ok, owner} =
      Accounts.register_user(valid_user_attributes(), skip_invite: true, welcomed: true)

    assert owner.welcomed_at
  end

  test "Rules & Roles: in the sidebar, for everyone; roles for those signed in", %{
    cooks: cooks
  } do
    html = build_conn() |> get(~p"/rules") |> html_response(200)
    assert html =~ ~s(id="rules-link")
    assert html =~ "Be kind"
    refute html =~ ~s(id="rules-form")

    member = user_fixture()
    conn = log_in_user(build_conn(), member)
    assert conn |> get(~p"/rules") |> html_response(200) =~ cooks.name

    conn = post(conn, ~p"/welcome", %{"role_ids" => [cooks.id], "return_to" => "/rules"})
    assert redirected_to(conn) == ~p"/rules"
    assert cooks.id in Enum.map(Access.roles_of(member), & &1.id)

    conn =
      post(log_in_user(build_conn(), member), ~p"/welcome", %{"return_to" => "//evil.example"})

    assert redirected_to(conn) == ~p"/"
  end

  test "administrators write About and Rules, and mark roles self-select", %{admin: admin} do
    conn = log_in_user(build_conn(), admin)
    {:ok, lv, _html} = live(conn, ~p"/admin")

    lv
    |> form("#settings-form", settings: %{server_about: "Hello", server_rules: "Rule one"})
    |> render_submit()

    assert Settings.get(:server_rules) == "Rule one"

    {:ok, lv, html} = live(conn, ~p"/admin/roles")
    assert html =~ "members can choose it"
    assert has_element?(lv, "#new-role-form input[type=radio][name='role[self_select]']")
  end
end
