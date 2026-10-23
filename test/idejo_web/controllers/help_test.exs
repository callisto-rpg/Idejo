# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Help (steward decision, 2026-10-23): no requirement ID.
defmodule IdejoWeb.HelpTest do
  use IdejoWeb.ConnCase, async: true

  alias IdejoWeb.ComposerCommands

  test "Help sits under Rules & Roles in the sidebar" do
    html = build_conn() |> get(~p"/") |> html_response(200)

    assert html =~
             ~r/id="rules-link".*?<\/a>\s*(<!--.*?-->\s*)?<a href="\/help"[^>]*id="help-link"/s
  end

  test "Help lists the keys that send, the signs and every ! command, without signing in" do
    html = build_conn() |> get(~p"/help") |> html_response(200)
    doc = LazyHTML.from_document(html)
    text = fn selector -> doc |> LazyHTML.query(selector) |> LazyHTML.text() end

    assert text.("h1") == "Help"
    sending = text.("#help-send dt")
    for key <- ["Enter", "Shift", "Ctrl"], do: assert(sending =~ key)
    assert text.("#help-send") =~ "Enter three times"
    # The window is this server's (15 s by default).
    assert text.("#help-send") =~ "more than 15 seconds old"

    signs = text.("#help-signs dt")
    for sign <- ["@", "+", "#", "/", "$", "!"], do: assert(signs =~ sign)

    for command <- ComposerCommands.all() do
      assert text.("#help-command-#{command.name} dt") =~ command.label
      assert text.("#help-command-#{command.name} dd") =~ command.help
    end

    assert Enum.map(ComposerCommands.all(), & &1.label) ==
             ["!image", "!new-topic", "!poll", "!schedule", "!spoiler"]
  end
end
