# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminCategoriesLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp slugs, do: Enum.map(Forum.list_categories(), & &1.slug)

  @tag req: "RP-03"
  test "RP-03 only administrators open the categories page" do
    conn =
      build_conn()
      |> log_in_user(user_with_role_fixture(:moderator))
      |> get(~p"/admin/categories")

    assert redirected_to(conn) == ~p"/"
  end

  @tag req: "RP-03"
  test "RP-03 an administrator creates categories from the form", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/admin/categories")
    assert html =~ "No categories yet"

    for name <- ~w(Announcements General Help) do
      lv |> form("#new-category-form", category: %{name: name}) |> render_submit()
    end

    assert slugs() == ~w(announcements general help)
    html = render(lv)
    assert html =~ "/c/announcements"
    refute html =~ "No categories yet"
  end

  @tag req: "RP-03"
  test "RP-03 form errors are shown", %{conn: conn, admin: admin} do
    {:ok, _} = Forum.create_category(admin, %{"name" => "Help", "slug" => "aide"})
    {:ok, lv, _html} = live(conn, ~p"/admin/categories")

    assert lv
           |> form("#new-category-form", category: %{name: "Other", slug: "aide"})
           |> render_submit() =~ "is already used by another category"
  end

  @tag req: "RP-03"
  test "RP-03 renaming, reordering and deleting from the page", %{conn: conn, admin: admin} do
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
    {:ok, lv, _html} = live(conn, ~p"/admin/categories")

    lv |> element("#category-#{help.id} button", "Edit") |> render_click()

    lv
    |> form("#edit-category-#{help.id}", edit: %{name: "Help & Support", description: "Ask here"})
    |> render_submit()

    assert lv |> element("#category-#{help.id}") |> render() =~ "Help &amp; Support"
    assert lv |> element("#category-#{help.id}") |> render() =~ "/c/help"

    lv |> element(~s(#category-#{help.id} button[phx-value-direction="up"])) |> render_click()
    assert slugs() == ~w(help general)

    lv |> element("#category-#{general.id} button", "Delete") |> render_click()
    assert slugs() == ~w(help)
  end

  @tag req: "RP-03"
  test "RP-03 the first has no up button and the last no down button", %{conn: conn, admin: admin} do
    {:ok, first} = Forum.create_category(admin, %{"name" => "First"})
    {:ok, last} = Forum.create_category(admin, %{"name" => "Last"})
    {:ok, lv, _html} = live(conn, ~p"/admin/categories")

    refute lv |> element("#category-#{first.id}") |> render() =~ ~s(phx-value-direction="up")
    assert lv |> element("#category-#{first.id}") |> render() =~ ~s(phx-value-direction="down")
    refute lv |> element("#category-#{last.id}") |> render() =~ ~s(phx-value-direction="down")
  end
end
