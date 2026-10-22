# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminCategoryIconsTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Forum.Category

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  @tag req: "RP-03"
  test "RP-03 a new category gets an icon and a colour, typed or picked", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/admin/categories")
    assert html =~ "No icon"
    assert has_element?(lv, "#new-category-form input[type=radio][value=soccer]")
    assert has_element?(lv, "#new-category-form input[type=color]")

    # The browser's colour picker fills in the hex field.
    html =
      lv
      |> form("#new-category-form", category: %{name: "Sport", colour_picker: "#dd3858"})
      |> render_change(%{"_target" => ["category", "colour_picker"]})

    assert html =~ ~s(value="#dd3858")

    lv
    |> form("#new-category-form",
      category: %{name: "Sport", icon: "soccer", colour: "#dd3858"}
    )
    |> render_submit()

    category = Idejo.Repo.get_by!(Category, name: "Sport")
    assert {category.icon, category.colour} == {"soccer", "#dd3858"}
    assert render(lv) =~ ~s(fill="#dd3858")
  end

  @tag req: "RP-03"
  test "RP-03 editing a category changes or removes its icon", %{conn: conn, admin: admin} do
    {:ok, category} = Forum.create_category(admin, %{"name" => "Food", "icon" => "food"})
    {:ok, lv, _html} = live(conn, ~p"/admin/categories")

    lv |> element("#category-#{category.id} button", "Edit") |> render_click()

    assert has_element?(
             lv,
             "#edit-category-#{category.id} input[type=radio][value=food][checked]"
           )

    html =
      lv
      |> form("#edit-category-#{category.id}", edit: %{colour: "nope"})
      |> render_change()

    assert html =~ "must look like #3366ff"

    lv
    |> form("#edit-category-#{category.id}", edit: %{icon: "", colour: "#123456"})
    |> render_submit()

    assert %{icon: nil, colour: "#123456"} = Idejo.Repo.reload!(category)
  end
end
