# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Requirements do
  @moduledoc """
  Reads requirement IDs from the specification sheets and the tests tagged with them
  (DV-02). Paths are relative to the project root, where `mix test` runs.
  """

  @mvp "Idejo — MVP Spec Sheet v0.1.md"
  @v1 "Community Platform — Spec Sheet v1.md"

  @doc """
  The IDs required for v0.1: the first cell of each row of the MVP sheet's requirements
  table, with ranges ("GM-01 to GM-14") and lists ("LI-01 to LI-03, LI-05") expanded.
  """
  @spec mvp() :: [String.t()]
  def mvp do
    [_, section] = String.split(File.read!(@mvp), "## 3. Requirements", parts: 2)
    [table | _] = String.split(section, "\n## ", parts: 2)

    for "| " <> row <- String.split(table, "\n"),
        [cell | _] = String.split(row, " |", parts: 2),
        Regex.match?(~r/\A[A-Z]{2}-\d{2}/, cell),
        part <- String.split(cell, ", "),
        id <- expand(part),
        uniq: true,
        do: id
  end

  defp expand(part) do
    case Regex.run(~r/\A([A-Z]{2})-(\d{2})(?: to [A-Z]{2}-(\d{2}))?\z/, part) do
      [_, prefix, from] -> [id(prefix, from)]
      [_, prefix, from, to] -> Enum.map(int(from)..int(to)//1, &id(prefix, &1))
    end
  end

  defp int(digits), do: String.to_integer(digits)
  defp id(prefix, n) when is_binary(n), do: id(prefix, int(n))
  defp id(prefix, n), do: prefix <> "-" <> String.pad_leading(Integer.to_string(n), 2, "0")

  @doc "Every ID the v1 sheet defines (its requirement tables)."
  @spec v1() :: [String.t()]
  def v1 do
    Regex.scan(~r/^\| ([A-Z]{2}-\d{2}) \|/m, File.read!(@v1), capture: :all_but_first)
    |> List.flatten()
  end

  @doc """
  The tests tagged with a requirement: `{id, test name, "file:line"}` for each
  `@tag req: "ID"` (or `@moduletag`) and the test that follows it.
  """
  @spec tagged_tests() :: [{String.t(), String.t() | nil, String.t()}]
  def tagged_tests do
    for file <- Path.wildcard("test/**/*_test.exs"),
        lines = file |> File.read!() |> String.split("\n"),
        {line, n} <- Enum.with_index(lines, 1),
        [_, id] <- [Regex.run(~r/^\s*@(?:module)?tag\b.*\breq:\s*"([A-Z]{2}-\d{2})"/, line)] do
      {id, lines |> Enum.drop(n) |> Enum.find_value(&test_name/1), "#{file}:#{n}"}
    end
  end

  defp test_name(line) do
    case Regex.run(~r/^\s*test\s+"([^"]*)"/, line) do
      [_, name] -> name
      nil -> nil
    end
  end
end
