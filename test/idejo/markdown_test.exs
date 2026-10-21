# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.MarkdownTest do
  use ExUnit.Case, async: true

  alias Idejo.Markdown

  @tag req: "TP-11"
  test "TP-11 Markdown renders formatting, lists, links, quotes and tables" do
    html =
      Markdown.to_html("""
      # Title

      Some *soft* and **strong** words, ~~gone~~, and https://example.org.

      - one
      - two

      > quoted

      | a | b |
      | - | - |
      | 1 | 2 |
      """)

    assert html =~ "<h1>Title</h1>"
    assert html =~ "<em>soft</em>"
    assert html =~ "<strong>strong</strong>"
    assert html =~ "<del>gone</del>"
    assert html =~ ~s(<a href="https://example.org")
    assert html =~ "<li>one</li>"
    assert html =~ "<blockquote>"
    assert html =~ "<table>"
  end

  @tag req: "TP-11"
  test "TP-11 code blocks and inline code keep their text as written" do
    html =
      Markdown.to_html("""
      Run `mix test` first.

      ```elixir
      def hello, do: "<b>world</b>"
      ```
      """)

    assert html =~ "<code>mix test</code>"
    assert html =~ ~r/<pre><code[^>]*>def hello, do: "&lt;b&gt;world&lt;\/b&gt;"/
    # No highlighting: it would need inline styles, which the CSP refuses (SP-05).
    refute html =~ "style="
  end
end
