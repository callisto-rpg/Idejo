# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings.Stylesheet do
  @moduledoc """
  AD-11: the server's own stylesheet (`custom_css`, Admin → Stylesheet) is checked before it
  is saved. It may style anything, but load nothing from elsewhere and run nothing (SP-04:
  no third-party resources; the content security policy, SP-05, refuses them as well):

  - no `@import` (it would load another stylesheet);
  - every `url(…)`, and every address in `image-set(…)`, stays on this server: a path
    (`/uploads/…`, `images/…`) or a `data:` image or font, never another site
    (`https:`, `//host`) or another scheme (`javascript:`);
  - nothing that ever ran script in a browser: `expression(…)`, `behavior:`,
    `-moz-binding`, `javascript:`, `vbscript:`;
  - no `</` (the text never closes an HTML element, wherever it is put).

  CSS escapes (`u\\72l(`) and comments are read away first, so they hide nothing.
  """

  @doc "`:ok`, or `{:error, reason}` in words for the admin."
  @spec check(String.t()) :: :ok | {:error, String.t()}
  def check(css) when is_binary(css) do
    if String.contains?(css, "</") do
      {:error, "must not contain \"</\""}
    else
      css |> plain() |> check_plain()
    end
  end

  defp check_plain(text) do
    cond do
      String.contains?(text, "@import") ->
        {:error, "must not use @import: it cannot load other stylesheets"}

      script =
          Enum.find(
            ~w(expression( -moz-binding javascript: vbscript:),
            &String.contains?(text, &1)
          ) ->
        {:error, "must not use #{String.trim_trailing(script, "(")}: it would run script"}

      Regex.match?(~r/(^|[;{\s])behavior\s*:/, text) ->
        {:error, "must not use behavior: it would run script"}

      address = Enum.find(addresses(text), &(not local?(&1))) ->
        {:error,
         "may only use addresses on this server (or data:), not #{inspect(String.slice(address, 0, 60))}"}

      true ->
        :ok
    end
  end

  # Comments out, escapes decoded (`\75 rl` is `url`), lowercase.
  defp plain(css) do
    css
    |> String.replace(~r{/\*.*?(\*/|\z)}s, " ")
    |> String.replace(~r/\\([0-9a-fA-F]{1,6})\s?/, fn match ->
      [_, hex] = Regex.run(~r/\\([0-9a-fA-F]{1,6})/, match)

      case Integer.parse(hex, 16) do
        {code, ""} when code in 1..0x10FFFF and code not in 0xD800..0xDFFF -> <<code::utf8>>
        _invalid -> " "
      end
    end)
    |> String.replace(~r/\\(.)/s, "\\1")
    |> String.downcase()
  end

  # Every url(…) target, and the strings in image-set(…) (where a string is an address).
  defp addresses(text) do
    urls =
      for [_ | groups] <- Regex.scan(~r/url\(\s*(?:["']([^"']*)["']|([^)]*?))\s*\)/, text),
          # A group that did not take part is left out of the match, or "" before another.
          do: groups |> Enum.reject(&(&1 == "")) |> List.first("") |> String.trim()

    sets =
      for [_, args] <- Regex.scan(~r/image-set\(([^)]*)\)/, text),
          [_, string] <- Regex.scan(~r/["']([^"']*)["']/, args),
          do: string

    urls ++ sets
  end

  defp local?(address) do
    address = String.trim(address)

    cond do
      String.starts_with?(address, "data:") -> true
      String.starts_with?(address, "//") -> false
      Regex.match?(~r/^[a-z][a-z0-9+.-]*:/, address) -> false
      true -> true
    end
  end
end
