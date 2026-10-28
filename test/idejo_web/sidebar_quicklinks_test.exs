# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The sidebar's links rolled into icons (steward decision, 2026-10-28): no requirement ID.
defmodule IdejoWeb.SidebarQuicklinksTest do
  use IdejoWeb.ConnCase, async: true

  test "a button at the right of All categories rolls the other links into their icons" do
    doc = build_conn() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    links = LazyHTML.query(doc, "#sidebar-quicklinks")

    assert links |> LazyHTML.query("a.sidebar-all[href='/']") |> LazyHTML.text() =~
             "All categories"

    # The three links, each with its name in a label the stylesheet hides once rolled.
    for {id, name} <- [
          {"tags-link", "Filter by tag"},
          {"rules-link", "Rules & Roles"},
          {"help-link", "Help"}
        ] do
      link = LazyHTML.query(links, "#sidebar-quicklinks-more ##{id}")
      assert link |> LazyHTML.query(".sidebar-link-label") |> LazyHTML.text() == name
      assert LazyHTML.attribute(link, "data-bubble") == [name]
    end

    # A toggle naming what it does, after the links (hidden without scripts).
    button = LazyHTML.query(links, "button#sidebar-quicklinks-roll")
    assert LazyHTML.attribute(button, "aria-pressed") == ["false"]
    assert LazyHTML.attribute(button, "aria-controls") == ["sidebar-quicklinks-more"]
    assert LazyHTML.attribute(button, "aria-label") == ["Show these links as icons only"]

    css = File.read!("assets/css/app.css")
    assert css =~ ".sidebar-roll { display: none; }"
    assert css =~ ~s([data-quicklinks="rolled"] {)

    # Remembered by the browser, applied before the first paint, kept when the sidebar is
    # swapped for a fresh one.
    theme = File.read!("assets/js/theme.js")
    assert theme =~ ~s|localStorage.getItem("idejo:quicklinks") === "rolled"|
    assert theme =~ ~s|document.documentElement.dataset.quicklinks = "rolled"|

    js = File.read!("assets/js/sidebar.js")
    assert js =~ ~s|const ROLLED = "idejo:quicklinks"|
    assert js =~ ~s|e.target.closest("#sidebar-quicklinks-roll")|
    assert js =~ ~r/export function applyFolds\(\) \{[^}]*syncRoll\(\)/s
  end
end
