# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Markdown do
  @moduledoc """
  Turns a message's Markdown source into the HTML stored next to it (FD-03).

  Raw HTML in the source is not passed through, and the result is sanitised as well, so the
  stored HTML is safe to show as is. No syntax highlighting: MDEx would colour code with
  inline styles, which the content security policy refuses (SP-05).

  Inline links (TP-10; steward decision, 2026-10-22): `references/1` finds what the text
  names, never in code or inside a link (`a@b.com` is a mail link):

    * `@username` - a user;
    * `+role` - a role, by its name as a slug (`+help-desk`);
    * `#slug` - a topic, `/slug` - a category, `$slug` - a tag.

  `to_html/2` with `links:` turns the ones it is given into links, keeping what the author
  typed unless it is given a label.
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

  # Every inline link, whole, for splitting text: @user, +role, #topic, /category, $tag. A
  # slug is letters and digits in parts joined by single dashes; roles and tags start with a
  # letter ("+1", "$5" stay text). None may follow a letter or digit ("C#", "and/or"), and a
  # /category is no part of a path ("/usr/bin", "a/b").
  @reference ~r"(?<![\w@])@[A-Za-z0-9_]{3,30}(?!\w)|(?<![\w+])\+[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*(?!\w)|(?<![\w#&])\#[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*(?!\w)|(?<![\w/.:~-])/[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*(?![\w/])|(?<![\w$])\$[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*(?!\w)"u

  @sigils %{"@" => :user, "+" => :role, "#" => :topic, "/" => :category, "$" => :tag}

  @typedoc "What an inline link names: its kind and its lowercased username or slug."
  @type inline_link :: {:user | :role | :topic | :category | :tag, String.t()}

  @doc """
  Renders Markdown to sanitised HTML. `links:` maps references (`references/1`) to
  `{path, label}`: each one written in the text becomes a link to `path`, showing `label`, or
  what the author typed when the label is nil.
  """
  @spec to_html(String.t(), keyword()) :: String.t()
  def to_html(markdown, opts \\ [])

  def to_html(markdown, opts) when is_binary(markdown) do
    case Keyword.get(opts, :links, %{}) do
      links when links == %{} ->
        MDEx.to_html!(markdown, @options)

      links ->
        markdown
        |> MDEx.parse_document!(@options)
        |> link_references(links)
        |> MDEx.to_html!(@options)
    end
  end

  @doc """
  Returns the inline links written in the Markdown, each once, outside code and links.
  """
  @spec references(String.t()) :: [inline_link()]
  def references(markdown) when is_binary(markdown) do
    if String.contains?(markdown, Map.keys(@sigils)) do
      markdown
      |> MDEx.parse_document!(@options)
      |> texts()
      |> Enum.flat_map(&Regex.scan(@reference, &1))
      |> Enum.map(fn [whole] -> reference(whole) end)
      |> Enum.uniq()
    else
      []
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

  defp reference(<<sigil::binary-size(1), name::binary>>),
    do: {Map.fetch!(@sigils, sigil), String.downcase(name)}

  # Text nodes outside links and images; code has no text nodes.
  defp texts(%MDEx.Text{literal: literal}), do: [literal]
  defp texts(%MDEx.Link{}), do: []
  defp texts(%MDEx.Image{}), do: []
  defp texts(%{nodes: nodes}), do: Enum.flat_map(nodes, &texts/1)
  defp texts(_node), do: []

  defp link_references(%MDEx.Link{} = node, _links), do: node
  defp link_references(%MDEx.Image{} = node, _links), do: node

  defp link_references(%{nodes: nodes} = node, links),
    do: %{node | nodes: Enum.flat_map(nodes, &expand(&1, links))}

  defp link_references(node, _links), do: node

  defp expand(%MDEx.Text{literal: literal}, links) do
    @reference
    |> Regex.split(literal, include_captures: true, trim: true)
    |> Enum.map(fn part ->
      case link_for(part, links) do
        nil ->
          %MDEx.Text{literal: part}

        {path, label} ->
          %MDEx.Link{url: path, title: "", nodes: [%MDEx.Text{literal: label || part}]}
      end
    end)
  end

  defp expand(node, links), do: [link_references(node, links)]

  # A part split out as a whole inline link, one of those given.
  defp link_for(part, links) do
    if Regex.match?(~r/\A(?:#{@reference.source})\z/u, part),
      do: Map.get(links, reference(part))
  end
end
