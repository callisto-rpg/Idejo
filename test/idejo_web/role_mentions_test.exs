# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.RoleMentionsTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access

  @tag req: "TP-10"
  test "TP-10 a +role leads to the role's page with its members; member and guest have none" do
    admin = user_with_role_fixture(:administrator)
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Help desk")})
    ada = user_fixture(%{display_name: "Ada"})
    :ok = Access.grant_role(ada, role)

    html = build_conn() |> get(~p"/r/#{Access.role_slug(role)}") |> html_response(200)
    assert html =~ role.name
    assert html =~ "1 member"
    assert html =~ ~s(href="/u/#{ada.id}")

    assert build_conn() |> get(~p"/r/moderator") |> html_response(200) =~ "Moderator"

    for slug <- ~w(member guest nobody-here) do
      assert_error_sent 404, fn -> get(build_conn(), ~p"/r/#{slug}") end
    end
  end

  @tag req: "TP-10"
  test "TP-10 the role editor sets who may tag a role" do
    admin = user_with_role_fixture(:administrator)
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Crew")})
    {:ok, lv, html} = live(log_in_user(build_conn(), admin), ~p"/admin/roles")
    assert html =~ "+moderator"

    lv |> element("#role-#{role.id} button", "Edit") |> render_click()

    html =
      lv
      |> form("#edit-role-#{role.id}", edit: %{mentionable: "true", mentions_below: "false"})
      |> render_submit()

    assert html =~ "can be tagged by everyone"
    assert Idejo.Repo.reload!(role).mentionable

    # Member and guest offer no mention settings.
    member = Access.built_in_role!(:member)
    lv |> element("#role-#{member.id} button", "Edit") |> render_click()
    refute has_element?(lv, "#edit-role-#{member.id} select")
  end
end
