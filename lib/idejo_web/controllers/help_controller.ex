# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.HelpController do
  @moduledoc """
  The Help page at `/help`, linked from the sidebar under "Rules & Roles" (steward decision,
  2026-10-23): the keys that send, the signs that link or suggest (`@`, `+`, `#`, `/`, `$`,
  `!`), every `!` command (`IdejoWeb.ComposerCommands`) and, last (steward decision,
  2026-10-28), "Formatting text": every Markdown format (`Idejo.Markdown`), what to type and
  how it shows, rendered as a message is. Public, no JavaScript needed.
  """
  use IdejoWeb, :controller

  alias Idejo.Messages.Body

  def show(conn, _params) do
    render(conn, :show,
      page_title: gettext("Help"),
      window: Idejo.Settings.get(:gm_window_seconds),
      unanswered: Idejo.Settings.get(:gm_unanswered_minutes),
      commands: IdejoWeb.ComposerCommands.all(),
      formatting: formatting()
    )
  end

  @doc """
  The formats, in the order the page shows them: `%{id, syntax, label, example}`, `example`
  the syntax rendered as a message's text is (nil for headings, which would join the page's
  outline). A new format in `Idejo.Markdown` joins this list.
  """
  @spec formatting() :: [map()]
  def formatting do
    [
      {"bold", "**" <> gettext("bold") <> "**", gettext("Bold.")},
      {"italics", "*" <> gettext("italics") <> "*",
       gettext("Italics. One underscore on each side works too.")},
      {"strikethrough", "~~" <> gettext("struck through") <> "~~", gettext("Struck through.")},
      {"highlight", "==" <> gettext("highlighted") <> "==", gettext("Highlighted.")},
      {"superscript", "x^2^",
       gettext("Superscript: everything between the two ^ is raised, spaces included.")},
      {"small", "-# " <> gettext("small text"),
       gettext("Small text, greyed out: at the start of a line, with a space after the #.")},
      {"code", "`" <> gettext("code") <> "`", gettext("Code, kept exactly as typed.")},
      {"code-block", "```\n" <> gettext("code on") <> "\n" <> gettext("several lines") <> "\n```",
       gettext("A block of code: ``` on a line before it and after it.")},
      {"quote", "> " <> gettext("quoted text"), gettext("A quote, at the start of a line.")},
      {"list", "- " <> gettext("one") <> "\n- " <> gettext("two"),
       gettext("A list: - or * at the start of each line.")},
      {"numbered", "1. " <> gettext("first") <> "\n2. " <> gettext("second"),
       gettext("A numbered list.")},
      {"link", "[" <> gettext("text") <> "](https://example.org)",
       gettext("A link. An address typed on its own becomes a link too.")},
      {"heading", "## " <> gettext("Heading"),
       gettext("A heading: one to six # at the start of a line, then a space.")},
      {"table", "| a | b |\n| - | - |\n| 1 | 2 |",
       gettext("A table: a line of names, a line of dashes, then the rows.")},
      {"emoji", ":smile:", gettext("An emoji, by its name between colons.")},
      {"escape", "\\*" <> gettext("not italics") <> "\\*",
       gettext("A \\ before a sign shows the sign itself.")}
    ]
    |> Enum.map(fn {id, syntax, label} ->
      %{
        id: id,
        syntax: syntax,
        label: label,
        example: if(id != "heading", do: Body.to_html(syntax))
      }
    end)
  end
end
