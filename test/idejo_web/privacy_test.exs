# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PrivacyTest do
  # Writes the privacy notice, a server-wide setting every test shares.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Settings

  @tag req: "AD-02"
  test "AD-02 administrators write the privacy notice, shown to everyone at /privacy", %{
    conn: conn
  } do
    html = conn |> get(~p"/privacy") |> html_response(200)
    assert html =~ "This server has not published a privacy notice yet."

    admin = user_with_role_fixture(:administrator)
    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    lv
    |> form("#settings-form", settings: %{privacy_notice: "We keep **little**."})
    |> render_submit()

    assert Settings.get(:privacy_notice) == "We keep **little**."

    page = build_conn() |> get(~p"/privacy") |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(page, "#privacy-notice strong") |> LazyHTML.text() == "little"
    refute LazyHTML.text(page) =~ "has not published"
  end

  @tag req: "AD-02"
  test "AD-02 every page's footer links to the privacy notice", %{conn: conn} do
    for path <- [~p"/", ~p"/users/sign-in", ~p"/privacy"] do
      footer = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

      assert LazyHTML.query(footer, "footer a#privacy-link") |> LazyHTML.attribute("href") == [
               "/privacy"
             ]
    end
  end
end
