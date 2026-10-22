# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CardStyleTest do
  use ExUnit.Case, async: true

  test "cards over the page are lined and lifted like the other boxes" do
    css = File.read!("assets/css/app.css")
    [card] = Regex.run(~r/^\.modal-box \{.*?^\}/ms, css)
    assert card =~ "border: 1px solid"
    assert card =~ "var(--shadow-lift)"
  end
end
