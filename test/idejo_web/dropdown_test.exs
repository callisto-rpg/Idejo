# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The app's dropdowns, the menus' arrows and the cards' look (steward decisions,
# 2026-10-23): no requirement ID.
defmodule IdejoWeb.DropdownTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, _} = Forum.create_category(admin, %{"name" => "Garden"})
    %{general: general}
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp query(doc, selector), do: LazyHTML.query(doc, selector)

  test "the search page's category is the app's dropdown, not the system's, and works without JavaScript",
       %{general: general} do
    doc = doc(build_conn(), ~p"/search")
    assert Enum.empty?(query(doc, "select"))

    dropdown = query(doc, "#search-form details#search-category.dropdown-select[data-dropdown]")
    assert Enum.count(dropdown) == 1
    # Named by its visible label and its choice; the first choice by default, as a select.
    assert ["search-category-label search-category-value"] =
             dropdown |> LazyHTML.query("summary") |> LazyHTML.attribute("aria-labelledby")

    assert LazyHTML.text(LazyHTML.query(dropdown, "#search-category-value")) == "All categories"

    assert ["category"] =
             dropdown |> LazyHTML.query("input:checked") |> LazyHTML.attribute("name")

    assert Enum.count(LazyHTML.query(dropdown, ".popup-menu input[type=radio][name=category]")) ==
             3

    # The chosen category stays chosen; the form sends it as the select did.
    doc = doc(build_conn(), ~p"/search?q=x&category=#{general.slug}")

    assert [slug] = doc |> query("#search-category input:checked") |> LazyHTML.attribute("value")
    assert slug == general.slug
    assert LazyHTML.text(query(doc, "#search-category-value")) == "General"
  end

  test "no template draws the system's select any more" do
    files =
      Path.wildcard("lib/idejo_web/**/*.{ex,heex}") --
        ["lib/idejo_web/components/core_components.ex"]

    assert Enum.filter(files, &(File.read!(&1) =~ "<select")) == []
  end

  test "the account and topic menus point like speech bubbles; dropdowns do not" do
    user = user_fixture()
    doc = doc(log_in_user(build_conn(), user), ~p"/search")
    assert Enum.count(query(doc, "#account-menu .account-panel.popup-menu.has-arrow")) == 1
    assert Enum.count(query(doc, "#topic-menu.popup-menu.has-arrow")) == 1
    assert Enum.empty?(query(doc, ".dropdown-select-menu.has-arrow"))

    css = File.read!("assets/css/app.css")
    assert css =~ ".popup-menu.has-arrow {"
    assert File.read!("assets/js/topic_menu.js") =~ ~s(el.style.setProperty("--arrow-x")
  end

  test "dialog cards take the menus' look" do
    css = File.read!("assets/css/app.css")
    [card] = Regex.run(~r/^\.modal-box \{.*?^\}/ms, css)
    assert card =~ "var(--card-opacity, 70%)"
    assert card =~ "blur(var(--card-blur, 4px))"
    assert card =~ "box-shadow: var(--shadow-lift);"
  end

  test "a click outside the account menu or a message's React choices, or Escape, closes them" do
    js = File.read!("assets/js/account_menu.js")
    assert js =~ ~s|const OUTSIDE_CLOSES = "#account-menu[open], .add-reaction[open]"|
    assert js =~ ~s|if (!el.contains(e.target)) el.open = false|
    assert js =~ ~s|if (e.key !== "Escape") return|
    assert File.read!("assets/js/app.js") =~ ~s(import "./account_menu")
  end
end
