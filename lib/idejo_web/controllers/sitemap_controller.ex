# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SitemapController do
  @moduledoc """
  `/sitemap.xml` and `/robots.txt` (SE-04). The sitemap lists the public pages, the ones a
  visitor without an account may view, at their canonical addresses: the home page, the
  categories and their topics. `robots.txt` names the sitemap, with this server's address.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  # XML, not HTML, and every address in it is escaped (escape/1).
  # sobelow_skip ["XSS.SendResp"]
  def sitemap(conn, _params) do
    entries =
      [{url(~p"/"), nil}] ++
        Enum.map(Forum.list_viewable_categories(nil), &{url(~p"/c/#{&1.slug}"), nil}) ++
        Enum.map(
          Forum.list_public_topics(),
          &{url(~p"/t/#{&1.id}/#{&1.slug}"), &1.last_activity_at}
        )

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, sitemap_xml(entries))
  end

  def robots(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "User-agent: *\nDisallow:\n\nSitemap: #{url(~p"/sitemap.xml")}\n")
  end

  defp sitemap_xml(entries) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      Enum.map(entries, &entry/1),
      "</urlset>\n"
    ]
  end

  defp entry({loc, nil}), do: ["  <url><loc>", escape(loc), "</loc></url>\n"]

  defp entry({loc, lastmod}) do
    [
      "  <url><loc>",
      escape(loc),
      "</loc><lastmod>",
      DateTime.to_iso8601(DateTime.truncate(lastmod, :second)),
      "</lastmod></url>\n"
    ]
  end

  # Slugs are plain ASCII, but the host could hold an & one day.
  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
