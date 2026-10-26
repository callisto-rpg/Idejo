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

  # Steward decision, 2026-10-25: at the right of the title, as in the account menu.
  test "Help and the account menu choose all, simple or no tutorial bubbles" do
    doc = build_conn() |> get(~p"/help") |> html_response(200) |> LazyHTML.from_document()

    toggle =
      LazyHTML.query(
        doc,
        ~s(header.page-intro .bubbles-toggle[aria-labelledby="help-bubbles-label"])
      )

    assert toggle |> LazyHTML.query("button[data-choice=on]") |> LazyHTML.text() =~ "All"
    assert toggle |> LazyHTML.query("button[data-choice=simple]") |> LazyHTML.text() =~ "Simple"
    assert toggle |> LazyHTML.query("button[data-choice=off]") |> LazyHTML.text() =~ "Off"
    assert doc |> LazyHTML.query("#help-bubbles-label") |> LazyHTML.text() == "Tutorial bubbles"

    member = Idejo.AccountsFixtures.user_fixture()
    html = build_conn() |> log_in_user(member) |> get(~p"/help") |> html_response(200)

    assert html
           |> LazyHTML.from_document()
           |> LazyHTML.query("#account-menu .bubbles-toggle button")
           |> Enum.count() == 3

    theme = File.read!("assets/js/theme.js")
    assert theme =~ ~s|localStorage.setItem("idejo:bubbles", choice)|

    # Simple (steward decision, 2026-10-26): the composer's caret bubbles stay, no hints.
    css = File.read!("assets/css/app.css")

    assert css =~
             ~s|[data-bubbles="simple"] :not(.composer-caret-bubbles) > .tutorial-bubble:not(.is-always),|

    assert css =~ ~s|[data-bubbles="simple"] .composer-hint { display: none; }|
    assert theme =~ "phx:set-bubbles"
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
    # And the unanswered message time (10 minutes by default).
    assert text.("#help-send") =~ "until it is 10 minutes old"

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
