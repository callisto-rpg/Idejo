# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.FooterTest do
  # The footer (attribution, source code, privacy) shows only on Help, Profile and account
  # and the admin pages (steward decision, 2026-11-03); Help is linked from every page's
  # sidebar, so the notice and the source stay one click away.
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  @notice "Powered by Idejo — © Mariano Pictet and contributors — AGPL-3.0"

  defp footer_link(html, id) do
    html |> LazyHTML.from_document() |> LazyHTML.query("footer a##{id}")
  end

  defp pages_with_footer(conn) do
    admin = user_with_role_fixture(:administrator)
    signed_in = log_in_user(conn, admin)
    {:ok, _lv, admin_html} = live(signed_in, ~p"/admin")
    {:ok, _lv, roles_html} = live(signed_in, ~p"/admin/roles")

    {:ok, _lv, profile_html} =
      live(log_in_user(build_conn(), user_fixture()), ~p"/users/settings")

    [
      {"help", conn |> get(~p"/help") |> html_response(200)},
      {"profile and account (LiveView)", profile_html},
      {"admin settings (LiveView)", admin_html},
      {"admin roles (LiveView)", roles_html}
    ]
  end

  @tag req: "LI-02"
  test "LI-02 Help and the settings pages show the attribution notice word for word, linked to idejo.org",
       %{conn: conn} do
    for {page, html} <- pages_with_footer(conn) do
      link = footer_link(html, "attribution")
      assert LazyHTML.text(link) |> String.trim() == @notice, page
      assert LazyHTML.attribute(link, "href") == ["https://idejo.org"], page
    end
  end

  @tag req: "LI-02"
  test "LI-02 the notice matches the NOTICE file" do
    assert File.read!("NOTICE") =~ @notice
  end

  @tag req: "LI-03"
  test "LI-03 Help and the settings pages link to the source code it runs; every page links Help",
       %{conn: conn} do
    for {page, html} <- pages_with_footer(conn) do
      link = footer_link(html, "source-code")
      assert LazyHTML.text(link) =~ "Source code", page
      assert LazyHTML.attribute(link, "href") == [Idejo.Source.url()], page
    end

    # Other pages have no footer, but their sidebar leads to Help.
    for path <- [~p"/", ~p"/users/sign-in", ~p"/search"] do
      doc = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
      assert doc |> LazyHTML.query("footer") |> Enum.count() == 0, path

      assert doc |> LazyHTML.query(~s(#sidebar a#help-link[href="/help"])) |> Enum.count() == 1,
             path
    end
  end
end
