# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.LogosTest do
  @moduledoc """
  The Idejo logos (steward decision, 2026-10-23): the small one before the server's name in
  the header and as the favicon, the full one above the sign-in, sign-up and setup pages.
  """
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  test "the header shows the small logo before the server's name; the favicon is the same" do
    doc = build_conn() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert doc
           |> LazyHTML.query(~s(#brand > img.brand-mark[src="/images/logo-small.png"][alt=""]))
           |> Enum.count() == 1

    assert doc |> LazyHTML.query("#brand .brand-name") |> LazyHTML.text() =~ "Idejo"

    assert doc
           |> LazyHTML.query(
             ~s(link[rel="icon"][type="image/png"][href="/images/logo-small.png"])
           )
           |> Enum.count() == 1
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

  test "the logo files are served, and the full logo turns white in the dark theme" do
    assert build_conn() |> get("/images/logo.svg") |> response(200) =~ "<svg"

    assert ["image/png" <> _] =
             build_conn() |> get("/images/logo.png") |> get_resp_header("content-type")

    small = build_conn() |> get("/images/logo-small.png") |> response(200)
    assert <<0x89, "PNG", _::binary>> = small
    assert build_conn() |> get("/favicon.ico") |> response(200) == small

    css = File.read!("assets/css/app.css")
    assert css =~ ~S|[data-theme="dark"] .full-logo { filter: invert(1); }|
  end
end
