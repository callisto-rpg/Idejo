// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// MentionGlow hook, on the message list (steward decision, 2026-10-25): an unread message
// that @mentions the reader or +mentions one of their roles (`data-mention-glow`, "mention"
// or "role-mention", from TopicLive) glows in its notification dot's colour once it is
// scrolled to: medium, bigger in 0.3 s, held 1 s, faded in 3 s. Meanwhile the tags naming
// the reader (`data-mention-tags` on the list: their `/u/…` and `/r/…` links) pulse three
// times. `data-glowing` is kept across patches (`JS.ignore_attributes`); each message glows
// once per page, a reconnect included.

const glowed = new Set()

// Enough of the message on screen: half of it, or, taller than the screen, a third of it.
const seen = entry =>
  entry.isIntersecting &&
  (entry.intersectionRatio >= 0.5 || entry.intersectionRect.height >= window.innerHeight / 3)

export const MentionGlow = {
  mounted() {
    this.observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (seen(entry)) this.glow(entry.target)
    }, {threshold: [0, 0.25, 0.5, 0.75, 1]})
    this.watch()
  },

  updated() { this.watch() },

  destroyed() { this.observer.disconnect() },

  watch() {
    for (const li of this.el.querySelectorAll("li[data-mention-glow]")) {
      if (!glowed.has(li.id) && !li.hidden) this.observer.observe(li)
    }
  },

  glow(li) {
    this.observer.unobserve(li)
    if (glowed.has(li.id)) return
    glowed.add(li.id)
    li.dataset.glowing = li.dataset.mentionGlow
    const box = li.querySelector(".message")
    box?.addEventListener("animationend", e => {
      if (e.animationName === "mention-glow") delete li.dataset.glowing
    })

    let tags = []
    try { tags = JSON.parse(this.el.dataset.mentionTags || "[]") } catch (_) { tags = [] }
    for (const link of li.querySelectorAll(".message-body a[href]")) {
      if (!tags.includes(link.getAttribute("href"))) continue
      link.classList.add("mention-pulse")
      link.addEventListener("animationend", () => link.classList.remove("mention-pulse"), {once: true})
    }
  },
}
