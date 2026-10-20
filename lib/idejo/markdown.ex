# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Markdown do
  @moduledoc """
  Turns a message's Markdown source into the HTML stored next to it (FD-03).

  Raw HTML in the source is not passed through, and the result is sanitised as well, so the
  stored HTML is safe to show as is. No syntax highlighting: MDEx would colour code with
  inline styles, which the content security policy refuses (SP-05).

  @mentions (TP-10): `mentions/1` finds the usernames written as `@name` in the text, never
  in code or inside a link (`a@b.com` is a mail link); `to_html/2` with `mentions:` turns the
  ones that name a user into a link to that user's URI path, `/u/{id}`.
  """

  @options [
    extension: [strikethrough: true, table: true, autolink: true, tasklist: true],
    render: [unsafe: false],
    syntax_highlight: nil,
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  # A username (AC-01: 3 to 30 letters, digits or _) after an @ that does not follow a letter,
  # digit or another @.
  @mention ~r/(?<![\w@])@([A-Za-z0-9_]{3,30})(?!\w)/u

  @doc """
  Renders Markdown to sanitised HTML. `mentions:` maps lowercased usernames to user ids;
  each `@name` among them becomes a link to `/u/{id}`, keeping what the author typed.
  """
  @spec to_html(String.t(), keyword()) :: String.t()
  def to_html(markdown, opts \\ [])

  def to_html(markdown, opts) when is_binary(markdown) do
    case Keyword.get(opts, :mentions, %{}) do
      users when users == %{} ->
        MDEx.to_html!(markdown, @options)

      users ->
        markdown
        |> MDEx.parse_document!(@options)
        |> link_mentions(users)
        |> MDEx.to_html!(@options)
    end
  end

  @doc """
  Returns the lowercased usernames mentioned in the Markdown, each once, outside code and
  links.
  """
  @spec mentions(String.t()) :: [String.t()]
  def mentions(markdown) when is_binary(markdown) do
    if String.contains?(markdown, "@") do
      markdown
      |> MDEx.parse_document!(@options)
      |> texts()
      |> Enum.flat_map(&Regex.scan(@mention, &1, capture: :all_but_first))
      |> Enum.map(fn [name] -> String.downcase(name) end)
      |> Enum.uniq()
    else
      []
    end
  end

  # Text nodes outside links and images; code has no text nodes.
  defp texts(%MDEx.Text{literal: literal}), do: [literal]
  defp texts(%MDEx.Link{}), do: []
  defp texts(%MDEx.Image{}), do: []
  defp texts(%{nodes: nodes}), do: Enum.flat_map(nodes, &texts/1)
  defp texts(_node), do: []

  defp link_mentions(%MDEx.Link{} = node, _users), do: node
  defp link_mentions(%MDEx.Image{} = node, _users), do: node

  defp link_mentions(%{nodes: nodes} = node, users),
    do: %{node | nodes: Enum.flat_map(nodes, &expand(&1, users))}

  defp link_mentions(node, _users), do: node

  defp expand(%MDEx.Text{literal: literal}, users) do
    @mention
    |> Regex.split(literal, include_captures: true, trim: true)
    |> Enum.map(fn part ->
      case mention_id(part, users) do
        nil -> %MDEx.Text{literal: part}
        id -> %MDEx.Link{url: "/u/" <> id, title: "", nodes: [%MDEx.Text{literal: part}]}
      end
    end)
  end

  defp expand(node, users), do: [link_mentions(node, users)]

  # A part split out as a whole mention, naming one of the users.
  defp mention_id("@" <> name = part, users) do
    if Regex.match?(~r/\A@[A-Za-z0-9_]{3,30}\z/, part), do: Map.get(users, String.downcase(name))
  end

  defp mention_id(_part, _users), do: nil
end
