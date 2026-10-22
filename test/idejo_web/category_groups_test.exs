# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CategoryGroupsTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Audit
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, garden} = Forum.create_category(admin, %{"name" => "Garden"})
    {:ok, games} = Forum.create_category(admin, %{"name" => "Games"})
    %{admin: admin, general: general, garden: garden, games: games}
  end

  defp texts(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  @tag req: "RP-03"
  test "RP-03 without groups: one Categories section, on the home page and in the sidebar" do
    html = build_conn() |> get(~p"/") |> html_response(200)
    assert texts(html, "main .section-divider") |> hd() == "Categories"
    assert texts(html, "#sidebar .sidebar-heading") == ["Categories"]
    assert texts(html, "#sidebar .sidebar-name") == ["General", "Garden", "Games"]
  end

  @tag req: "RP-03"
  test "RP-03 with groups: their names head their categories, ungrouped last as Other", %{
    admin: admin,
    general: general,
    garden: garden,
    games: games
  } do
    {:ok, hobbies} = Forum.create_group(admin, %{"name" => "Hobbies"})
    {:ok, outside} = Forum.create_group(admin, %{"name" => "Outside"})
    {:ok, _} = Forum.update_category(admin, games, %{"group_id" => hobbies.id})
    {:ok, _} = Forum.update_category(admin, garden, %{"group_id" => outside.id})

    html = build_conn() |> get(~p"/") |> html_response(200)

    assert texts(html, "main section > .section-divider") |> Enum.take(3) == [
             "Hobbies",
             "Outside",
             "Other"
           ]

    assert texts(html, "#sidebar .sidebar-group-title") == ["Hobbies", "Outside", "Other"]
    assert texts(html, "#sidebar details[open] .sidebar-name") == ["Games", "Garden", "General"]

    # Reordering and deleting groups: categories stay, ungrouped.
    {:ok, _} = Forum.move_group(admin, outside, :up)
    {:ok, _} = Forum.delete_group(admin, hobbies)
    assert Idejo.Repo.reload!(games).group_id == nil
    assert Idejo.Repo.reload!(general).group_id == nil

    html = build_conn() |> get(~p"/") |> html_response(200)
    assert texts(html, "#sidebar .sidebar-group-title") == ["Outside", "Other"]

    changes = Enum.map(Audit.list_entries(), & &1.change)

    assert Enum.all?(
             ~w(category_group.create category_group.reorder category_group.delete),
             &(&1 in changes)
           )
  end

  @tag req: "RP-03"
  test "RP-03 administrators manage groups and give categories one in Admin → Categories", %{
    admin: admin,
    garden: garden
  } do
    {:ok, lv, _html} = live(log_in_user(build_conn(), admin), ~p"/admin/categories")

    lv |> form("#new-group-form", group: %{name: "Outside"}) |> render_submit()
    [group] = Forum.list_groups()
    assert has_element?(lv, "#group-#{group.id}", "Outside")

    lv |> element("#category-#{garden.id} button", "Edit") |> render_click()
    lv |> form("#edit-category-#{garden.id}", edit: %{group_id: group.id}) |> render_submit()
    assert Idejo.Repo.reload!(garden).group_id == group.id
    assert has_element?(lv, "#category-#{garden.id} .badge", "Outside")

    lv |> element("#group-#{group.id} button", "Rename") |> render_click()
    lv |> form("#edit-group-#{group.id}", group_edit: %{name: "Outdoors"}) |> render_submit()
    assert has_element?(lv, "#group-#{group.id}", "Outdoors")

    assert lv
           |> form("#new-group-form", group: %{name: "outdoors"})
           |> render_submit() =~ "is already used by another group"
  end
end
