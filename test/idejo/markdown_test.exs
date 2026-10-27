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

  # Steward decision, 2026-10-28.
  @tag req: "TP-11"
  test "TP-11 superscript, highlight and small text, as in Discord" do
    assert Markdown.to_html("E = mc^2^") == "<p>E = mc<sup>2</sup></p>"
    assert Markdown.to_html("a ==bright== b") == "<p>a <mark>bright</mark> b</p>"

    assert Markdown.to_html("Big news\n-# small **print**") ==
             "<p>Big news</p>\n<p><sub>small <strong>print</strong></sub></p>"

    # Small text needs its space and the start of a line; no subscript, so every <sub> is it.
    assert Markdown.to_html("-#tight") == "<p>-#tight</p>"
    refute Markdown.to_html("H~2~O") =~ "<sub>"
    assert Markdown.to_html("x ^ y ^ z, a == b") == "<p>x ^ y ^ z, a == b</p>"
    # Never inside code.
    assert Markdown.to_html("`x^2^ ==a==`") == "<p><code>x^2^ ==a==</code></p>"
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
