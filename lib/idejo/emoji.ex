# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Emoji do
  @moduledoc """
  Emoji (TP-17; steward decision, 2026-10-22): the GitHub/Slack names from gemoji, drawn with
  Twemoji images served by the app (`/emoji/{code}.svg`, SP-04), and the server's own
  reactions drawn from `/reactions/{name}.png` (`:agree:`, `:bruh:`…). Data and credits:
  `priv/emoji/README.md`.

  An emoji is a map: `name` (the key, as written between colons), `char` (the Unicode emoji,
  nil for the server's own), `src` (its image) and `category`.
  """

  @data Path.expand("../../priv/emoji/emoji.json", __DIR__)
  @external_resource @data

  # The server's own reactions, in reactions/ (steward's work, CC-BY-4.0).
  @own ~w(agree disagree this same yes no bruh nice oof thank-you true)

  # The reaction picker's first choices (steward decision).
  @defaults ~w(agree disagree this same yes no joy heart)

  @type t :: %{name: String.t(), char: String.t() | nil, src: String.t(), category: String.t()}

  @standard (for entry <- Jason.decode!(File.read!(@data)) do
               %{
                 name: hd(entry["names"]),
                 names: entry["names"],
                 char: entry["emoji"],
                 src: "/emoji/#{entry["file"]}.svg",
                 category: entry["category"]
               }
             end)

  @own_entries Enum.map(
                 @own,
                 &%{name: &1, char: nil, src: "/reactions/#{&1}.png", category: "Server"}
               )

  # Every name, also the extra ones ("+1", "thumbsup"), to its emoji.
  @by_name Map.new(
             Enum.flat_map(@standard, fn e -> Enum.map(e.names, &{&1, Map.delete(e, :names)}) end) ++
               Enum.map(@own_entries, &{&1.name, &1})
           )

  # Typed emoji, with and without the U+FE0F variation selector ("❤" and "❤️").
  @by_char Map.new(
             Enum.flat_map(@standard, fn e ->
               e = Map.delete(e, :names)
               [{e.char, e}, {String.replace(e.char, "️", ""), e}]
             end)
           )

  @categories ["Server" | @standard |> Enum.map(& &1.category) |> Enum.uniq()]

  @doc ~S|The emoji a name stands for ("joy", "+1", "agree"), or nil.|
  @spec lookup(String.t()) :: t() | nil
  def lookup(name) when is_binary(name), do: Map.get(@by_name, name)

  @doc "The emoji a typed character (one grapheme) is, or nil."
  @spec by_char(String.t()) :: t() | nil
  def by_char(char) when is_binary(char), do: Map.get(@by_char, char)

  @doc "The reaction picker's first choices: the server's own six, then joy and heart."
  @spec defaults() :: [t()]
  def defaults, do: Enum.map(@defaults, &lookup/1)

  @doc """
  Every emoji, in groups: `[{category, [emoji]}]`, the server's own first. With a query, only
  the emoji with a name containing it.
  """
  @spec groups(String.t()) :: [{String.t(), [t()]}]
  def groups(query \\ "") do
    query = query |> String.trim() |> String.downcase() |> String.trim(":")

    entries =
      Enum.map(@own_entries ++ @standard, fn e ->
        {e, Map.get(e, :names, [e.name])}
      end)
      |> Enum.filter(fn {_e, names} ->
        query == "" or Enum.any?(names, &String.contains?(&1, query))
      end)
      |> Enum.map(fn {e, _names} -> Map.delete(e, :names) end)
      |> Enum.group_by(& &1.category)

    for category <- @categories, entries[category], do: {category, entries[category]}
  end
end
