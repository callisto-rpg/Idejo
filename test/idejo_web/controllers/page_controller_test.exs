# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PageControllerTest do
  use IdejoWeb.ConnCase

  test "GET / shows the server name", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "<h1"
    assert response =~ "Idejo"
    refute response =~ "Phoenix"
  end
end
