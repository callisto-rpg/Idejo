# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.LogosTest do
  @moduledoc """
  The Idejo logos (steward decisions, 2026-10-23 and 2026-10-24): the small one before the
  server's name in the header, the favicon, the full one above the sign-in, sign-up and setup
  pages.
  """
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  test "the header shows the small logo before the server's name, and the favicon" do
    doc = build_conn() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert doc
           |> LazyHTML.query(~s(#brand > img.brand-mark[src="/images/logo-small.svg"][alt=""]))
           |> Enum.count() == 1

    assert doc |> LazyHTML.query("#brand .brand-name") |> LazyHTML.text() =~ "Idejo"

    assert doc
           |> LazyHTML.query(~s(link[rel="icon"][type="image/png"][href="/images/favicon.png"]))
           |> Enum.count() == 1
  end

  @tag req: "AD-02"
  test "AD-02 every page carries the website theme's colours, in both themes" do
    html = build_conn() |> get(~p"/") |> html_response(200)

    [style] =
      Regex.run(~r/<style[^>]* nonce="[^"]+">\s*(:root,\[data-theme=light\][^<]*)/, html,
        capture: :all_but_first
      )

    # Text on the gold primary is near-black; the backgrounds are the page's.
    assert style =~ "--color-primary:#daa304ff;--color-primary-content:#111111;"
    assert style =~ "--color-secondary:#f2c94c;"
    assert style =~ "--color-accent:#b8860b;"
    assert style =~ "--color-base-200:#fdfcf6;"
    assert style =~ "[data-theme=dark]{"
    assert style =~ "--color-base-200:#1d1a00;"
  end

  test "the sign-in and sign-up pages show the full logo" do
    for path <- [~p"/users/sign-in", ~p"/users/sign-up"] do
      html = build_conn() |> get(path) |> html_response(200)
      assert html =~ ~s(src="/images/logo.svg" alt="Idejo" class="full-logo"), path
    end

    # Not the other pages.
    conn = log_in_user(build_conn(), user_fixture())
    refute conn |> get(~p"/") |> html_response(200) =~ "full-logo"
  end

  test "the logo files are served; the full logo is in colour, the same in both themes" do
    assert build_conn() |> get("/images/logo.svg") |> response(200) =~ "<svg"

    assert ["image/png" <> _] =
             build_conn() |> get("/images/logo.png") |> get_resp_header("content-type")

    assert build_conn() |> get("/images/logo-small.svg") |> response(200) =~ "<svg"
    small = build_conn() |> get("/images/logo-small.png") |> response(200)
    assert <<0x89, "PNG", _::binary>> = small

    favicon = build_conn() |> get("/images/favicon.png") |> response(200)
    assert <<0x89, "PNG", _::binary>> = favicon
    assert build_conn() |> get("/favicon.ico") |> response(200) == favicon

    refute File.read!("assets/css/app.css") =~ "invert(1)"
  end
end
