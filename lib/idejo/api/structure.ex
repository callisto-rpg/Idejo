# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Api.Structure do
  @moduledoc """
  What a message holds, as structured objects (AP-11; steward decision, 2026-11-10), so a
  client never parses idejo's Markdown extensions to know it.

    * `mentions/1` reads the inline links (TP-10) from the stored HTML (FD-03), where they
      were resolved as the author could view them when written: `@user` → `/u/{id}`,
      `+role` → `/r/{slug}`, `#topic` → `/t/{id}`, `/category` → `/c/{slug}`, `$tag` →
      `/tags?tags[]={slug}`. Their text is what readers see (`@robin`, `#Garden plans`).
    * `images/1` reads the Markdown's images: uploads (TP-12) by their file name, and
      others (GIFs) by their address.

  Pure functions: the caller loads what they refer to.
  """

  @sigils %{"u" => "user", "r" => "role", "t" => "topic", "c" => "category"}

  @link ~r{<a href="(/(u|r|t|c)/([^"/?#]+)|/tags\?tags(?:%5B%5D|\[\])=([^"&]+))"[^>]*>(.*?)</a>}s

  @type mention :: %{type: String.t(), ref: String.t(), text: String.t()}

  @doc """
  The inline links of a message's HTML, in order, each once: `%{type, ref, text}`, `ref`
  being the id (users, topics) or the slug (roles, categories, tags).
  """
  @spec mentions(String.t() | nil) :: [mention()]
  def mentions(nil), do: []

  def mentions(html) when is_binary(html) do
    @link
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn
      [_href, kind, ref, "", text] -> %{type: @sigils[kind], ref: ref, text: text(text)}
      [_href, "", "", slug, text] -> %{type: "tag", ref: URI.decode(slug), text: text(text)}
      [_href, kind, ref, text] -> %{type: @sigils[kind], ref: ref, text: text(text)}
    end)
    |> Enum.uniq_by(&{&1.type, &1.ref})
  end

  # The link's text without markup, entities read back.
  defp text(html) do
    html
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
  end

  @image ~r/!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/
  @upload ~r"\A/uploads/([0-9a-f-]{36}\.(?:jpg|png|gif|webp))\z"

  @type image :: %{url: String.t(), upload: String.t() | nil, alt: String.t()}

  @doc """
  The images of a message's Markdown, in order, each once: `%{url, upload, alt}`, `upload`
  being the upload's file name (`<id>.<ext>`) when it is one of this server's.
  """
  @spec images(String.t() | nil) :: [image()]
  def images(nil), do: []

  def images(markdown) when is_binary(markdown) do
    if String.contains?(markdown, "![") do
      @image
      |> Regex.scan(markdown, capture: :all_but_first)
      |> Enum.map(fn [alt, url] -> %{url: url, upload: upload(url), alt: alt} end)
      |> Enum.uniq_by(& &1.url)
    else
      []
    end
  end

  defp upload(url) do
    case Regex.run(@upload, url, capture: :all_but_first) do
      [name] -> name
      nil -> nil
    end
  end
end
