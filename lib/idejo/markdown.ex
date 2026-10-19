# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Markdown do
  @moduledoc """
  Turns a message's Markdown source into the HTML stored next to it (FD-03).

  Raw HTML in the source is not passed through, and the result is sanitised as well, so the
  stored HTML is safe to show as is. No syntax highlighting: MDEx would colour code with
  inline styles, which the content security policy refuses (SP-05).
  """

  @options [
    extension: [strikethrough: true, table: true, autolink: true, tasklist: true],
    render: [unsafe: false],
    syntax_highlight: nil,
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  @doc """
  Renders Markdown to sanitised HTML.
  """
  @spec to_html(String.t()) :: String.t()
  def to_html(markdown) when is_binary(markdown), do: MDEx.to_html!(markdown, @options)
end
