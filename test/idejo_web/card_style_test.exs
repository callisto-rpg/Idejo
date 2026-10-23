# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CardStyleTest do
  use ExUnit.Case, async: true

  @css File.read!("assets/css/app.css")

  defp rule(selector) do
    [rule] = Regex.run(~r/^\s*#{Regex.escape(selector)} \{.*?^\s*\}/ms, @css)
    rule
  end

  test "cards over the page are lined and lifted like the other boxes" do
    card = rule(".modal-box")
    assert card =~ "border: 1px solid"
    assert card =~ "var(--shadow-lift)"
  end

  test "everything that opens over the page shares one thin line" do
    for selector <- ~w(.modal-box .welcome-card .popup-menu .add-reaction-panel .suggestions),
        do: assert(rule(selector) =~ "border: 1px solid var(--overlay-line)", selector)
  end
end
