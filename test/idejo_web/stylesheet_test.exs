# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.StylesheetTest do
  # Writes the server-wide stylesheet setting, which every test shares.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Settings
  alias IdejoWeb.ThemeController

  test "the default stylesheet: cards like the menus (70%, 4px of blur), overlays at 80% and 6px" do
    css = Settings.default(:custom_css)
    assert css =~ "--menu-opacity: 70%;"
    assert css =~ "--menu-blur: 4px;"
    # Steward decision, 2026-10-23: dialog cards follow the menus.
    assert css =~ "--card-opacity: var(--menu-opacity);"
    assert css =~ "--card-blur: var(--menu-blur);"
    assert css =~ "--overlay-opacity: 80%;"
    assert css =~ "--overlay-blur: 6px;"
    assert css =~ ~r/\.modal-box \{[^}]*backdrop-filter: blur\(var\(--card-blur\)\)/
    assert css =~ ~r/\.welcome-card \{[^}]*backdrop-filter: blur\(var\(--overlay-blur\)\)/
  end

  test "/theme.css serves it as CSS; pages link it by version, after Idejo's styles" do
    css = Settings.get(:custom_css)
    conn = get(build_conn(), ~p"/theme.css?v=#{ThemeController.version(css)}")
    assert response(conn, 200) == css
    assert response_content_type(conn, :css)
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(get(build_conn(), ~p"/theme.css"), "cache-control") == ["no-cache"]

    html = build_conn() |> get(~p"/") |> html_response(200)
    app = :binary.match(html, "/assets/css/app.css") |> elem(0)
    theme = :binary.match(html, "/theme.css?v=#{ThemeController.version(css)}") |> elem(0)
    assert app < theme
  end

  test "administrators edit, save and reset the stylesheet in Admin → Stylesheet" do
    admin = user_with_role_fixture(:administrator)
    {:ok, lv, html} = live(log_in_user(build_conn(), admin), ~p"/admin/stylesheet")
    assert html =~ "--card-blur: var(--menu-blur);"

    lv
    |> form("#stylesheet-form", theme: %{custom_css: ".brand-name { color: red; }"})
    |> render_submit()

    assert Settings.get(:custom_css) == ".brand-name { color: red; }"
    assert response(get(build_conn(), ~p"/theme.css"), 200) =~ "color: red"

    lv |> element("#stylesheet-reset") |> render_click()
    assert Settings.get(:custom_css) == Settings.default(:custom_css)
    assert render(lv) =~ "Stylesheet reset to the default."

    # Only administrators.
    conn =
      build_conn()
      |> log_in_user(user_with_role_fixture(:moderator))
      |> get(~p"/admin/stylesheet")

    assert redirected_to(conn) == ~p"/"
  end
end
