# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InfoBoxesTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Settings.InfoBoxes

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    %{admin: admin, general: general}
  end

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)

  defp texts(html, selector),
    do: html |> query(selector) |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

  @tag req: "AD-02"
  test "AD-02 info boxes show before the categories, drawn like them, for everyone", %{
    admin: admin,
    general: general
  } do
    {:ok, welcome} =
      InfoBoxes.create(admin, %{
        "title" => "Welcome",
        "icon" => "general",
        "colour" => "#0FA05C",
        "body_md" => "Read the **rules** and <script>alert(1)</script> [help](/help)."
      })

    {:ok, _} = InfoBoxes.create(admin, %{"title" => "Events", "body_md" => ""})
    assert welcome.colour == "#0fa05c"

    html = build_conn() |> get(~p"/") |> html_response(200)

    assert texts(html, "#categories > li h3") == ["Welcome", "Events", "General"]
    card = "#info-box-#{welcome.id}"
    assert html |> query("#{card}.category-card.info-box-#{welcome.id}") |> Enum.count() == 1
    assert html |> query("#{card} .category-card-head svg.category-mark") |> Enum.count() == 1
    # FD-03: the Markdown's sanitised HTML; links stay links, scripts are dropped.
    assert html |> query("#{card} .message-body strong") |> Enum.count() == 1
    assert html |> query(~s(#{card} .message-body a[href="/help"])) |> Enum.count() == 1
    refute html =~ "alert(1)</script>"
    # Its colour reaches the card's lines through the nonce'd style, like a category's.
    assert html =~ ".info-box-#{welcome.id}{--cat:#0fa05c}"
    assert html =~ ".cat-#{general.id}{--cat:"
  end

  # Steward decision, 2026-10-26: "Show title and icon" off leaves the text alone.
  @tag req: "AD-02"
  test "AD-02 an info box can hide its title and icon, audited", %{conn: conn, admin: admin} do
    {:ok, box} = InfoBoxes.create(admin, %{"title" => "Note", "body_md" => "Just text."})
    assert box.show_head

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/info-boxes")
    lv |> element(~s(button[aria-label="Edit Note"])) |> render_click()

    lv
    |> form("#info-box-form", box: %{show_head: "false"})
    |> render_submit()

    assert [%{after: %{"show_head" => false}} | _] =
             Enum.filter(Audit.list_entries(), &(&1.change == "info_box.update"))

    html = build_conn() |> get(~p"/") |> html_response(200)
    card = "#info-box-#{box.id}"
    assert html |> query("#{card} .category-card-head") |> Enum.count() == 0
    assert texts(html, "#{card} .message-body") == ["Just text."]
  end

  @tag req: "AD-02"
  test "AD-02 with no category, the info boxes still show, without the empty notice", %{
    admin: admin
  } do
    {:ok, _} = InfoBoxes.create(admin, %{"title" => "Soon", "body_md" => "Opening soon."})
    html = build_conn() |> get(~p"/") |> html_response(200)
    assert texts(html, "#categories > li h3") |> Enum.member?("Soon")
  end

  @tag req: "AD-02"
  test "AD-02 admins create, edit, reorder and delete info boxes, each change audited", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/info-boxes")

    view
    |> form("#info-box-form", box: %{title: "", body_md: "x"})
    |> render_submit()

    assert render(view) =~ "can&#39;t be blank"

    view
    |> form("#info-box-form", box: %{title: "Welcome", body_md: "Hello *all*", icon: "general"})
    |> render_change()

    # The editor's preview, for the admin alone.
    view |> element("#box_body_md-preview-tab") |> render_click()
    assert view |> element("#box_body_md-preview") |> render() =~ "<em>all</em>"
    view |> element("#box_body_md-write-tab") |> render_click()

    view
    |> form("#info-box-form", box: %{title: "Welcome", body_md: "Hello *all*", icon: "general"})
    |> render_submit()

    view
    |> form("#info-box-form", box: %{title: "Rules", colour: "#123456", body_md: "Be kind."})
    |> render_submit()

    [welcome, rules] = InfoBoxes.list()
    assert welcome.body_html =~ "<em>all</em>"
    assert rules.colour == "#123456"

    view |> element(~s(button[phx-click="edit"][phx-value-id="#{rules.id}"])) |> render_click()
    assert view |> element("#info-box-form-heading") |> render() =~ "Rules"

    view
    |> form("#info-box-form", box: %{title: "House rules", body_md: "Be kind, always."})
    |> render_submit()

    view
    |> element(
      ~s(button[phx-click="move"][phx-value-id="#{welcome.id}"][phx-value-direction="down"])
    )
    |> render_click()

    assert Enum.map(InfoBoxes.list(), & &1.title) == ["House rules", "Welcome"]

    view
    |> element(~s(button[phx-click="delete"][phx-value-id="#{welcome.id}"]))
    |> render_click()

    assert Enum.map(InfoBoxes.list(), & &1.title) == ["House rules"]

    changes = Enum.map(Audit.list_entries(), & &1.change)

    assert Enum.all?(
             ~w(info_box.create info_box.update info_box.reorder info_box.delete),
             &(&1 in changes)
           )
  end

  # Steward request, 2026-11-13: before the categories, or in a section, first or last.
  @tag req: "AD-02"
  test "AD-02 an info box goes before the categories or in a section, at its start or end", %{
    conn: conn,
    admin: admin,
    general: general
  } do
    n = System.unique_integer([:positive])
    {:ok, clubs} = Forum.create_group(admin, %{"name" => "Clubs #{n}"})

    {:ok, chess} =
      Forum.create_category(admin, %{"name" => "Chess #{n}", "group_id" => clubs.id})

    box = fn title, attrs ->
      {:ok, box} = InfoBoxes.create(admin, Map.merge(%{"title" => title}, attrs))
      box
    end

    top = box.("Top", %{"place" => "before"})
    first = box.("First", %{})
    club = box.("Club", %{"place" => "group:" <> clubs.id})
    club_end = box.("Club end", %{"place" => "group:" <> clubs.id, "at_end" => "true"})
    other_end = box.("Other end", %{"place" => "other", "at_end" => true})

    assert {top.placement, first.placement, club.group_id} == {"before", "first", clubs.id}
    assert club_end.at_end and other_end.placement == "other"

    html = build_conn() |> get(~p"/") |> html_response(200)
    assert texts(html, "#info-boxes-before > li h3") == ["Top"]

    # Sections: the group's first, then "Other" (the ungrouped General).
    assert texts(html, "#categories > li h3") == ["First", "Club", chess.name, "Club end"]
    assert texts(html, "#categories-1 > li h3") == [general.name, "Other end"]

    # A group with nothing shown gives the first section.
    {:ok, _} = Forum.update_category(admin, chess, %{"group_id" => nil})
    html = build_conn() |> get(~p"/") |> html_response(200)
    assert texts(html, "#categories > li h3") |> List.first() == "First"
    assert "Club" in texts(html, "#categories > li h3")
    refute "Club" in texts(html, "#info-boxes-before > li h3")

    assert {:error, changeset} = InfoBoxes.create(admin, %{"title" => "X", "place" => "side"})
    assert changeset.errors[:place]

    # The admin page sets it, and lists where each one is.
    {:ok, lv, _html} = live(conn |> log_in_user(admin), ~p"/admin/info-boxes")
    assert render(lv) =~ "Before the categories"

    lv
    |> form("#info-box-form", box: %{title: "Late", place: "group:" <> clubs.id, at_end: "true"})
    |> render_submit()

    late = Enum.find(InfoBoxes.list(), &(&1.title == "Late"))
    assert {late.placement, late.group_id, late.at_end} == {"group", clubs.id, true}
    assert has_element?(lv, "#info-box-#{late.id}-place", "at the end")
  end

  @tag req: "AD-02"
  test "AD-02 only administrators reach the info boxes page", %{conn: conn} do
    member = user_fixture()

    assert {:error, {:redirect, _}} =
             conn |> log_in_user(member) |> live(~p"/admin/info-boxes")
  end
end
