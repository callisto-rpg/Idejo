// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// KLIPY's adapter (steward decision, 2026-11-03; server side: Idejo.Gifs.Klipy). On KLIPY's
// standard terms (docs.klipy.com/integration-requirements) the browser calls the API itself
// and the GIFs load from the URLs it returns, unchanged; results keep the order and make-up
// KLIPY gives them. Ads come only when they are switched on for the key in KLIPY's Partner
// Panel; Idejo shows no ads, so they must stay off there (docs/admin-guide.md).
const API = "https://api.klipy.com/api/v1"
const PER_PAGE = 24

// One file of a GIF: the size wanted, else any other; WebP (smaller, animated in every
// current browser), else the GIF itself.
const file = (files, sizes) => {
  for (const size of sizes) {
    const formats = files?.[size]
    const found = formats?.webp?.url ? formats.webp : formats?.gif
    if (found?.url) return {url: found.url, width: found.width, height: found.height}
  }
  return null
}

const item = gif => {
  const preview = file(gif.file, ["sm", "xs", "md", "hd"])
  const full = file(gif.file, ["md", "hd", "sm", "xs"])
  if (!preview || !full) return null
  return {id: String(gif.id), slug: gif.slug, title: gif.title || "", preview, full}
}

export const klipy = {
  // A page of GIFs: the popular ones without a query, else the search's.
  // Resolves to {items, more}; rejects when the API cannot be reached.
  async page({key, filter, query, page}) {
    const params = new URLSearchParams({page: String(page), per_page: String(PER_PAGE)})
    let path = "trending"
    if (query) {
      path = "search"
      params.set("q", query)
      params.set("content_filter", filter || "medium")
    }
    const response = await fetch(`${API}/${encodeURIComponent(key)}/gifs/${path}?${params}`, {
      credentials: "omit",
      referrerPolicy: "no-referrer"
    })
    if (!response.ok) throw new Error(`KLIPY ${response.status}`)
    const body = await response.json()
    const data = body?.data || {}
    const items = (data.data || []).filter(gif => gif.type !== "ad").map(item).filter(Boolean)
    return {items, more: Boolean(data.has_next)}
  },

  // KLIPY's share trigger, which helps it rank: the GIF chosen and the search that found it.
  // No user identifier is sent. Failures do not matter.
  shared({key, gif, query}) {
    fetch(`${API}/${encodeURIComponent(key)}/gifs/share/${encodeURIComponent(gif.slug)}`, {
      method: "POST",
      credentials: "omit",
      referrerPolicy: "no-referrer",
      headers: {"content-type": "application/json"},
      body: JSON.stringify(query ? {q: query} : {})
    }).catch(() => {})
  }
}
