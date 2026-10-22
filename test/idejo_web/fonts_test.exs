# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.FontsTest do
  use IdejoWeb.ConnCase, async: true

  test "titles in Fraunces, text in Rubik, both served by the app (SP-04)" do
    css = File.read!("assets/css/app.css")
    assert css =~ ~s(--font-title: "Fraunces")
    assert css =~ ~s(--font-body: "Rubik")
    refute css =~ ~r/fonts\.(googleapis|gstatic)\.com/

    files = Regex.scan(~r{url\("/fonts/([^"]+)"\)}, css, capture: :all_but_first)
    assert length(files) == 15

    for [file] <- files do
      assert File.exists?(Path.join("priv/static/fonts", file)), "#{file} is missing"
    end

    assert build_conn() |> get("/fonts/rubik-latin-wght-normal.woff2") |> response(200)
  end
end
