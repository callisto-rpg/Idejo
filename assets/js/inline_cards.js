// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Inline links (TP-10): @user, +role, #topic, /category and $tag are links to their pages,
// which work without JavaScript. In a topic, the InlineLinks hook opens the link's card in a
// dialog instead, unless the reader asked for a new tab or window. When the server has no
// card for the reader (they may not view it), the link is followed after all.

// What a link in a message names, from its address: {kind, ref}, or null.
export function cardFor(href) {
  let url
  try { url = new URL(href, window.location.origin) } catch (_e) { return null }
  if (url.origin !== window.location.origin) return null
  const parts = url.pathname.split("/").filter(Boolean)
  if (parts.length === 2 && parts[0] === "u") return {kind: "user", ref: parts[1]}
  if (parts.length === 2 && parts[0] === "r") return {kind: "role", ref: parts[1]}
  if (parts.length >= 2 && parts[0] === "t") return {kind: "topic", ref: parts[1]}
  if (parts.length === 2 && parts[0] === "c") return {kind: "category", ref: parts[1]}
  const tags = url.searchParams.getAll("tags[]")
  if (parts.length === 1 && parts[0] === "tags" && tags.length === 1) return {kind: "tag", ref: tags[0]}
  return null
}

export const InlineLinks = {
  mounted() {
    this.el.addEventListener("click", e => {
      const link = e.target.closest(".message-body a[href]")
      if (!link || e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return
      const card = cardFor(link.getAttribute("href"))
      if (!card) return
      e.preventDefault()
      InlineCard.opener = link
      this.pushEvent("show_card", card, ({shown}) => {
        if (!shown) window.location.assign(link.href)
      })
    })
  },
}

// The card's <dialog>, rendered while the server holds a card: shown as a modal (focus moves
// into it, Escape closes it), and on closing the focus goes back to the link.
export const InlineCard = {
  opener: null,

  mounted() {
    this.el.addEventListener("close", () => this.pushEvent("hide_card", {}))
    this.el.addEventListener("click", e => { if (e.target === this.el) this.el.close() })
    this.el.showModal()
  },

  destroyed() {
    if (InlineCard.opener && document.contains(InlineCard.opener)) InlineCard.opener.focus()
    InlineCard.opener = null
  },
}
