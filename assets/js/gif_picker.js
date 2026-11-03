// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The GIF overlay (steward decisions, 2026-11-03; IdejoWeb.GifComponents): `!gif` and the
// graphical composer's GIF button send `idejo:gif-open`; this opens the dialog, shows the
// provider's popular GIFs, then what the search box asks for (a moment after typing stops),
// and "More GIFs" adds the next page. A chosen GIF goes to the composer as Markdown
// (`idejo:gif`), the dialog closes and the focus goes back to the box. The provider is
// reached from the browser, through its adapter (assets/js/gifs/).
import {providers} from "./gifs/index"

const SEARCH_DELAY_MS = 350

// The Markdown of a GIF: its title as the alt text, so excerpts and screen readers read it.
export function gifMarkdown(gif, label) {
  const alt = (gif.title || label).replace(/[[\]\n]/g, " ").trim() || label
  return `![${alt}](${gif.full.url})`
}

export const GifPicker = {
  mounted() {
    this.adapter = providers[this.el.dataset.provider]
    this.search = this.el.querySelector("#gif-search")
    this.results = this.el.querySelector("[data-results]")
    this.more = this.el.querySelector("[data-more]")
    this.status = this.el.querySelector("[data-status]")
    this.empty = this.el.querySelector("[data-empty]")
    this.failed = this.el.querySelector("[data-failed]")
    this.query = null
    this.page = 1
    this.loading = 0
    this.opener = null

    this.onOpen = e => this.open(e.detail?.opener)
    window.addEventListener("idejo:gif-open", this.onOpen)

    this.el.querySelector("[data-search]").addEventListener("submit", e => {
      e.preventDefault()
      clearTimeout(this.timer)
      this.load(this.search.value.trim(), 1)
    })
    this.search.addEventListener("input", () => {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.load(this.search.value.trim(), 1), SEARCH_DELAY_MS)
    })
    this.more.addEventListener("click", () => this.load(this.query, this.page + 1))
    this.el.querySelector("[data-close]").addEventListener("click", () => this.el.close())
    // A click on the backdrop (the dialog itself, outside its card) closes it.
    this.el.addEventListener("click", e => { if (e.target === this.el) this.el.close() })
    this.el.addEventListener("close", () => this.opener?.focus())

    this.results.addEventListener("click", e => {
      const button = e.target.closest("button[data-index]")
      if (button) this.choose(this.items[Number(button.dataset.index)])
    })
  },

  destroyed() {
    window.removeEventListener("idejo:gif-open", this.onOpen)
    clearTimeout(this.timer)
  },

  open(opener) {
    if (!this.adapter) return
    this.opener = opener || null
    if (!this.el.open) this.el.showModal()
    this.search.focus()
    this.search.select()
    if (this.query === null) this.load("", 1)
  },

  async load(query, page) {
    const ticket = ++this.loading
    if (page === 1) {
      this.items = []
      this.results.replaceChildren()
    }
    this.show({status: true})
    try {
      const {items, more} = await this.adapter.page({
        key: this.el.dataset.key,
        filter: this.el.dataset.filter,
        query,
        page
      })
      // A later search won the race: this answer is old.
      if (ticket !== this.loading) return
      this.query = query
      this.page = page
      this.add(items)
      this.show({empty: this.items.length === 0, more})
    } catch (_e) {
      if (ticket === this.loading) this.show({failed: true})
    }
  },

  add(items) {
    for (const gif of items) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "gif-result"
      button.dataset.index = String(this.items.length)
      button.setAttribute("aria-label", gif.title || this.el.dataset.labelGif)
      const img = document.createElement("img")
      img.src = gif.preview.url
      img.alt = ""
      img.loading = "lazy"
      img.decoding = "async"
      img.referrerPolicy = "no-referrer"
      if (gif.preview.width) img.width = gif.preview.width
      if (gif.preview.height) img.height = gif.preview.height
      button.appendChild(img)
      this.results.appendChild(button)
      this.items.push(gif)
    }
  },

  show({status = false, empty = false, failed = false, more = false}) {
    this.status.hidden = !status
    this.empty.hidden = !empty
    this.failed.hidden = !failed
    this.more.hidden = !more || status
  },

  choose(gif) {
    if (!gif) return
    window.dispatchEvent(new CustomEvent("idejo:gif", {
      detail: {markdown: gifMarkdown(gif, this.el.dataset.labelGif)}
    }))
    this.adapter.shared({key: this.el.dataset.key, gif, query: this.query})
    this.el.close()
  }
}
