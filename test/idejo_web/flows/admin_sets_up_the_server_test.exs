# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Flows.AdminSetsUpTheServerTest do
  @moduledoc """
  MVP §4, "Admin sets up the server": the exit check of M1. It drives the real pages, in
  order, as the admin would: the first-run wizard, categories, roles and the permission
  grid, invite-only registration and an invite link, then a pilot member joining with it.
  """
  # Turns the setup redirect on, so not async.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Settings
  alias Idejo.Setup

  setup do
    Application.put_env(:idejo, :setup_redirect, true)
    on_exit(fn -> Application.put_env(:idejo, :setup_redirect, false) end)
  end

  defp role(name), do: Enum.find(Access.list_roles(), &(&1.name == name))
  defp category(slug), do: Forum.get_category_by_slug(slug)

  defp set(lv, role, right, effect) do
    lv |> form("#permission-#{role.id}-#{right}", %{effect: effect}) |> render_change()
  end

  @tag flow: "admin-sets-up-the-server"
  test "the admin sets up the server", %{conn: conn} do
    # 1. The install opens on the wizard: server name, owner account and SMTP settings.
    assert redirected_to(get(conn, ~p"/")) == ~p"/setup"

    conn =
      post(conn, ~p"/setup", %{
        "setup" => %{
          "code" => Setup.token(),
          "owner" => %{
            "email" => "olga@example.org",
            "username" => "olga",
            "display_name" => "Olga Owner",
            "password" => valid_user_password()
          },
          "settings" => %{
            "server_name" => "Lumière",
            "mail_from" => "forum@example.org",
            "smtp_host" => "smtp.example.org",
            "smtp_port" => "587",
            "smtp_security" => "starttls"
          }
        }
      })

    assert redirected_to(conn) == ~p"/admin/email"
    conn = recycle(conn)
    owner = Accounts.get_user_by_email("olga@example.org")
    assert Access.owner?(owner)
    assert Settings.get(:smtp_host) == "smtp.example.org"
    # Set up: the wizard is gone and the home page carries the server name.
    assert redirected_to(get(conn, ~p"/setup")) == ~p"/"
    assert conn |> get(~p"/") |> html_response(200) =~ "Lumière"

    # 2. Categories, then their order: Help moves above General.
    {:ok, lv, _html} = live(conn, ~p"/admin/categories")

    for name <- ["Announcements", "General", "Help"] do
      lv |> form("#new-category-form", category: %{name: name}) |> render_submit()
    end

    lv |> element(~s(button[aria-label="Move Help up"])) |> render_click()
    assert Enum.map(Forum.list_categories(), & &1.slug) == ~w(announcements help general)

    # 3. Custom roles, then the permission grid per category.
    {:ok, lv, _html} = live(conn, ~p"/admin/roles")

    for {name, colour} <- [{"Team", "#2255aa"}, {"Members", ""}] do
      lv |> form("#new-role-form", role: %{name: name, colour: colour}) |> render_submit()
    end

    team = role("Team")
    members = role("Members")
    member = Access.built_in_role!(:member)
    guest = Access.built_in_role!(:guest)

    # Announcements: only Team starts topics and posts there, and Team moderates it.
    {:ok, lv, _html} = live(conn, ~p"/admin/permissions/announcements")
    set(lv, member, :start, "deny")
    set(lv, member, :post, "deny")
    set(lv, team, :start, "allow")
    set(lv, team, :post, "allow")
    set(lv, team, :moderate, "allow")

    # Help: members only; visitors cannot read it, the custom Members role can.
    lv |> element(~s(nav[aria-label="Where the settings apply"] a), "Help") |> render_click()
    set(lv, guest, :view, "deny")
    set(lv, members, :view, "allow")

    assert Access.permissions(category("announcements")) == %{
             {member.id, :start} => :deny,
             {member.id, :post} => :deny,
             {team.id, :start} => :allow,
             {team.id, :post} => :allow,
             {team.id, :moderate} => :allow
           }

    # 4. Registration becomes invite-only, and an invite link is made for a pilot member.
    {:ok, lv, _html} = live(conn, ~p"/admin")

    lv
    |> form("#settings-form", settings: %{registration_mode: "invite_only"})
    |> render_submit()

    assert Settings.get(:registration_mode) == "invite_only"

    {:ok, lv, _html} = live(conn, ~p"/admin/invites")
    lv |> element("#create-invite") |> render_click()

    [_, invite_path] =
      Regex.run(~r{value="https?://[^/"]+(/users/sign-up\?invite=[^"]+)"}, render(lv))

    # Without an invite, nobody can join.
    refused =
      build_conn()
      |> post(~p"/users/sign-up", %{"user" => valid_user_attributes(invite_code: "")})
      |> html_response(200)

    assert refused =~ "is not valid, used or expired"

    # The pilot member opens the link, signs up and verifies their email address.
    [_, code] = Regex.run(~r/invite=(.+)$/, invite_path)
    pilot_conn = build_conn()
    assert pilot_conn |> get(invite_path) |> html_response(200) =~ ~s(value="#{code}")

    pilot_conn =
      post(pilot_conn, ~p"/users/sign-up", %{
        "user" =>
          valid_user_attributes(email: "pia@example.org", username: "pia", invite_code: code)
      })

    assert redirected_to(pilot_conn) == ~p"/"

    assert_email_sent(fn email ->
      assert [{_name, "pia@example.org"}] = email.to
      [_, token] = Regex.run(~r{/users/confirm/([\w-]+)}, email.text_body)
      send(self(), {:confirm_token, token})
    end)

    assert_received {:confirm_token, token}
    pilot_conn = post(recycle(pilot_conn), ~p"/users/confirm/#{token}")
    pia = Accounts.get_user_by_email("pia@example.org")
    assert Accounts.confirmed?(pia)

    # What the grid set is what people get.
    announcements = category("announcements")
    help = category("help")
    general = category("general")

    assert Access.can?(pia, :view, announcements)
    refute Access.can?(pia, :post, announcements)
    assert Access.can?(pia, :post, general)
    refute Access.can?(nil, :view, help)

    home = pilot_conn |> recycle() |> get(~p"/") |> html_response(200)
    assert home =~ "Announcements"
    assert home =~ "Help"

    visitor_home = build_conn() |> get(~p"/") |> html_response(200)
    assert visitor_home =~ "Announcements"
    refute visitor_home =~ "Help"

    # The owner puts the pilot member in Team: now they post in Announcements.
    {:ok, lv, _html} = live(conn, ~p"/admin/users/#{pia.id}")
    lv |> form("#assign-role-form", assign: %{role_id: team.id}) |> render_submit()
    assert Access.can?(pia, :post, announcements)
    assert Access.can?(pia, :moderate, announcements)
    refute Access.can?(pia, :moderate, general)

    # Every admin change is in the audit log, made by the owner.
    changes = Audit.list_entries(limit: 200)
    assert Enum.all?(changes, &(&1.admin_id == owner.id))

    for change <- ~w(category.create category.reorder role.create permission.update
                     settings.update invite.create role.grant) do
      assert Enum.any?(changes, &(&1.change == change)), "no #{change} in the audit log"
    end
  end
end
