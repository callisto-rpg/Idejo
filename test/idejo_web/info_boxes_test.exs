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

  @tag req: "AD-02"
  test "AD-02 only administrators reach the info boxes page", %{conn: conn} do
    member = user_fixture()

    assert {:error, {:redirect, _}} =
             conn |> log_in_user(member) |> live(~p"/admin/info-boxes")
  end
end
