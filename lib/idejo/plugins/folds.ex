# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Plugins.Folds do
  @moduledoc """
  Collapsible text (steward request, 2026-11-09): a `collapse` plugin's command at the start
  of a line, outside code, folds the lines right below it that start with `:`.

      !collapse Spoilers for chapter 3     ← the title, shown
      :The butler did it.                  ← hidden until unrolled (the ":" and one space go)
      :He had the key.

  With nothing after the command, the next line (not starting with `:`) is the title. Without
  any `:` line it stays plain text. `split/2` cuts the Markdown into plain parts and folds;
  `Idejo.Messages.Body` renders each and draws a fold as `<details><summary>`, so readers
  unroll it by its arrow or its title, with no script. Rendered when the message is written
  and stored (FD-03): a fold stays when its plugin goes later (steward decision).
  """

  @fence ~r/^\s*(```|~~~)/

  @type segment :: {:text, String.t()} | {:fold, String.t(), String.t()}

  @doc """
  The Markdown as plain parts and folds, for the given commands (without `!`), or `nil` when
  it holds no fold.
  """
  @spec split(String.t(), [String.t()]) :: [segment()] | nil
  def split(_markdown, []), do: nil

  def split(markdown, commands) do
    pattern = ~r/^!(#{Enum.map_join(commands, "|", &Regex.escape/1)})(?:[ \t]+(.*))?[ \t]*$/

    if String.contains?(markdown, "!") and Regex.match?(~r/^!/m, markdown) do
      segments = markdown |> String.split("\n") |> walk(pattern, false, [], [])
      if Enum.any?(segments, &match?({:fold, _, _}, &1)), do: segments
    end
  end

  # `text` gathers plain lines (reversed), `acc` the segments (reversed).
  defp walk([], _pattern, _fenced?, text, acc), do: Enum.reverse(flush(text, acc))

  defp walk([line | rest], pattern, fenced?, text, acc) do
    cond do
      Regex.match?(@fence, line) ->
        walk(rest, pattern, not fenced?, [line | text], acc)

      not fenced? and Regex.match?(pattern, line) ->
        fold(line, rest, pattern, text, acc)

      true ->
        walk(rest, pattern, fenced?, [line | text], acc)
    end
  end

  defp fold(line, rest, pattern, text, acc) do
    title = pattern |> Regex.run(line) |> Enum.at(2, "") |> String.trim()

    {title, after_title} =
      case {title, rest} do
        {"", [next | more]} -> if hidden?(next), do: {"", rest}, else: {String.trim(next), more}
        _ -> {title, rest}
      end

    {hidden, remaining} = Enum.split_while(after_title, &hidden?/1)

    if hidden == [] or title == "" do
      walk(rest, pattern, false, [line | text], acc)
    else
      body = Enum.map_join(hidden, "\n", &String.replace(&1, ~r/^:[ \t]?/, ""))
      walk(remaining, pattern, false, [], [{:fold, title, body} | flush(text, acc)])
    end
  end

  defp hidden?(line), do: String.starts_with?(line, ":")

  defp flush([], acc), do: acc
  defp flush(text, acc), do: [{:text, text |> Enum.reverse() |> Enum.join("\n")} | acc]
end
