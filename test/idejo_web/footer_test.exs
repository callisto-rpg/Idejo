# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.FooterTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  @notice "Powered by Idejo — © Mariano Pictet and contributors — AGPL-3.0"

  defp footer_link(html, id) do
    html |> LazyHTML.from_document() |> LazyHTML.query("footer a##{id}")
  end

  defp pages(conn) do
    admin = user_with_role_fixture(:administrator)
    {:ok, _lv, admin_html} = conn |> log_in_user(admin) |> live(~p"/admin")

    [
      {"home", conn |> get(~p"/") |> html_response(200)},
      {"sign-in", conn |> get(~p"/users/sign-in") |> html_response(200)},
      {"admin (LiveView)", admin_html}
    ]
  end

  @tag req: "LI-02"
  test "LI-02 every page shows the attribution notice word for word, linked to idejo.org", %{
    conn: conn
  } do
    for {page, html} <- pages(conn) do
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
  test "LI-03 every page links to the source code it runs", %{conn: conn} do
    for {page, html} <- pages(conn) do
      link = footer_link(html, "source-code")
      assert LazyHTML.text(link) =~ "Source code", page
      assert LazyHTML.attribute(link, "href") == [Idejo.Source.url()], page
    end
  end
end
