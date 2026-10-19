# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminCategoryDeleteLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, old} = Forum.create_category(admin, %{"name" => "Old"})
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Forum.create_topic(user_fixture(), old, %{"title" => "One", "body" => "Hi"})
    %{conn: log_in_user(conn, admin), admin: admin, old: old, general: general, topic: topic}
  end

  @tag req: "RP-03"
  test "RP-03 deleting a category with topics asks to move or archive them", %{
    conn: conn,
    old: old,
    general: general,
    topic: topic
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/categories")
    assert lv |> element("#category-#{old.id}") |> render() =~ "1 topic"

    lv |> element("#category-#{old.id} button", "Delete") |> render_click()
    assert has_element?(lv, "#delete-category-#{old.id} input[value='move:#{general.id}']")
    assert has_element?(lv, "#delete-category-#{old.id} input[value='archive']")

    html =
      lv
      |> form("#delete-category-#{old.id}", %{topics: "move:#{general.id}"})
      |> render_submit()

    assert html =~ "Category “Old” deleted."
    assert Repo.reload!(topic).category_id == general.id
  end

  @tag req: "TP-14"
  test "TP-14 archiving from the page adds the Archive, which has no Delete", %{
    conn: conn,
    old: old,
    topic: topic
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/categories")
    lv |> element("#category-#{old.id} button", "Delete") |> render_click()
    lv |> form("#delete-category-#{old.id}", %{topics: "archive"}) |> render_submit()

    topic = Repo.reload!(topic)
    assert topic.state == "archived"

    [archive] = Enum.filter(Forum.list_categories(), & &1.archive)
    assert has_element?(lv, "#category-#{archive.id} .badge", "Archive")
    refute has_element?(lv, "#category-#{archive.id} button", "Delete")

    # The archived topic says it is read only.
    html = conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    assert html =~ "Archived: read only"
  end

  @tag req: "TP-14"
  test "TP-14 the Archive offers no New topic, even to administrators", %{
    conn: conn,
    admin: admin
  } do
    {:ok, archive} = Forum.archive_category(admin)
    refute conn |> get(~p"/c/#{archive.slug}") |> html_response(200) =~ "/new"

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/c/#{archive.slug}/new")
    assert to == "/c/#{archive.slug}"
  end
end
