# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The sidebar always shows on wide screens and the header's button is not shown in the bar
# (steward decision, 2026-11-03): no requirement ID.
defmodule IdejoWeb.SidebarAlwaysOpenTest do
  use IdejoWeb.ConnCase, async: true

  test "the sidebar never hides on wide screens; the drawer's button shows only on focus" do
    css = File.read!("assets/css/app.css")
    refute css =~ ~s([data-sidebar="hidden"])
    assert css =~ "@media (min-width: 1024px) { .sidebar-toggle { display: none; } }"
    assert css =~ ".sidebar-toggle:not(:focus-visible) {"

    theme = File.read!("assets/js/theme.js")
    refute theme =~ ~s(dataset.sidebar = "hidden")
    assert theme =~ ~s{localStorage.removeItem("idejo:sidebar")}
    refute File.read!("assets/js/sidebar.js") =~ ~s{setItem("idejo:sidebar"}

    # The button stays in the page for keyboard and screen-reader users, named.
    doc = build_conn() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    button = LazyHTML.query(doc, "header button#sidebar-toggle")
    assert LazyHTML.attribute(button, "aria-controls") == ["sidebar"]
    assert LazyHTML.attribute(button, "aria-label") == ["Show or hide the categories"]
  end
end
