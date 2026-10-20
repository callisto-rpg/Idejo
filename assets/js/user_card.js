// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// @mentions (TP-10). A mention is a link to the user's URI, /u/{id}, which works without
// JavaScript. In a topic, the Mentions hook opens the user card in a dialog instead, unless
// the reader asked for a new tab or window.
const MENTION = ".message-body a[href^='/u/']"

export const Mentions = {
  mounted() {
    this.el.addEventListener("click", e => {
      const link = e.target.closest(MENTION)
      if (!link || e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return
      e.preventDefault()
      UserCard.opener = link
      this.pushEvent("show_user", {id: link.getAttribute("href").slice("/u/".length)})
    })
  },
}

// The card's <dialog>, rendered while the server holds a card: shown as a modal (focus moves
// into it, Escape closes it), and on closing the focus goes back to the mention.
export const UserCard = {
  opener: null,

  mounted() {
    this.el.addEventListener("close", () => this.pushEvent("hide_user", {}))
    this.el.addEventListener("click", e => { if (e.target === this.el) this.el.close() })
    this.el.showModal()
  },

  destroyed() {
    if (UserCard.opener && document.contains(UserCard.opener)) UserCard.opener.focus()
    UserCard.opener = null
  },
}
