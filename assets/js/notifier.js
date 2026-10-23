// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Notifier hook (steward decision, 2026-10-23), on IdejoWeb.NotifierLive: live notifications.
//
// Bubbles: each notification shows for ten seconds at the top right, newest on top; the
// older ones slide down, and past three the oldest goes. Pointing at a bubble or focusing
// it pauses its time (AX: timing adjustable). Its colour says what it is (the sidebar dots'
// colours: grey, blue, orange, red; purple for a reaction). Nothing about the topic on
// screen bubbles: the reader sees it live there.
//
// Sidebar, and the count on the header's Unread link: fetched again from /sidebar shortly
// after a notification (once the topic view has marked what it showed as read), when the
// tab comes back, and on a schedule that slows down as the page gets older: every 5 s for
// the first 20 s after a page loads (a live navigation counts), then every 30 s, then past
// 5 minutes every 10 minutes (steward decision, 2026-10-23). Neither is swapped while it
// has the focus.
//
// Glow: a new message in a topic of the sidebar makes its name glow like sent text burns
// in, half as strongly (.sidebar-burn): on a notification, and on "topic_activity", which
// the open topic's view sends to the window. A sidebar swapped in mid-glow carries on.

const LIFETIME = 10000
const BURN_MS = 2200
const MOST = 3
const SETTLE = 1500

// How long to wait before the next scheduled fetch, by how long ago the page loaded.
const nextPoll = age => (age < 20000 ? 5000 : age < 300000 ? 30000 : 600000)

const reduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches
const viewedTopic = () => document.getElementById("topic-live")?.dataset.topicId

export const Notifier = {
  mounted() {
    this.box = this.el.querySelector("#bubbles")
    this.handleEvent("notification", n => this.notify(n))
    this.glowing = new Map()
    this.onActivity = e => this.glow(e.detail.topic_id)
    window.addEventListener("phx:topic_activity", this.onActivity)
    this.onVisible = () => { if (document.visibilityState === "visible") this.refreshSidebar() }
    document.addEventListener("visibilitychange", this.onVisible)
    // This view outlives live navigation: each new page starts the schedule again.
    this.onPage = e => { if (["initial", "redirect", "patch"].includes(e.detail?.kind)) this.schedule() }
    window.addEventListener("phx:page-loading-stop", this.onPage)
    this.schedule()
  },

  destroyed() {
    clearTimeout(this.poll)
    clearTimeout(this.settle)
    document.removeEventListener("visibilitychange", this.onVisible)
    window.removeEventListener("phx:page-loading-stop", this.onPage)
    window.removeEventListener("phx:topic_activity", this.onActivity)
  },

  schedule() {
    clearTimeout(this.poll)
    this.loadedAt = Date.now()
    const tick = () => {
      this.refreshSidebar()
      this.poll = setTimeout(tick, nextPoll(Date.now() - this.loadedAt))
    }
    this.poll = setTimeout(tick, nextPoll(0))
  },

  notify(n) {
    if (n.kind !== "reaction") {
      this.glow(n.topic_id)
      clearTimeout(this.settle)
      this.settle = setTimeout(() => this.refreshSidebar(), SETTLE)
    }
    if (n.topic_id !== viewedTopic()) this.show(n)
  },

  show(n) {
    const bubble = this.bubble(n)
    this.flip(() => {
      this.box.prepend(bubble)
      const extra = [...this.box.children].filter(b => !b.classList.contains("is-leaving")).slice(MOST)
      extra.forEach(b => b.remove())
    })
    this.time(bubble)
  },

  bubble(n) {
    const bubble = document.createElement("div")
    bubble.className = `bubble is-${n.kind.replace("_", "-")}`

    const link = document.createElement("a")
    link.className = "bubble-link"
    link.href = n.href
    const text = document.createElement("span")
    text.className = "bubble-text"
    text.textContent = n.text
    if (n.emoji) {
      const img = document.createElement("img")
      img.src = n.emoji.src
      img.alt = n.emoji.alt
      img.className = "emoji"
      text.append(" ", img)
    }
    link.append(text)
    if (n.excerpt) {
      const excerpt = document.createElement("span")
      excerpt.className = "bubble-excerpt"
      excerpt.textContent = n.excerpt
      link.append(excerpt)
    }

    const close = document.createElement("button")
    close.type = "button"
    close.className = "bubble-close"
    close.setAttribute("aria-label", this.el.dataset.dismiss)
    close.textContent = "×"
    close.addEventListener("click", () => this.dismiss(bubble))

    bubble.append(link, close)
    return bubble
  },

  // Ten seconds, paused while pointed at or focused.
  time(bubble) {
    let left = LIFETIME
    let started = Date.now()
    let timer = setTimeout(() => this.dismiss(bubble), left)
    const pause = () => { clearTimeout(timer); left -= Date.now() - started }
    const resume = () => {
      if (bubble.matches(":hover") || bubble.contains(document.activeElement)) return
      started = Date.now()
      timer = setTimeout(() => this.dismiss(bubble), Math.max(left, 1500))
    }
    bubble.addEventListener("mouseenter", pause)
    bubble.addEventListener("focusin", pause)
    bubble.addEventListener("mouseleave", resume)
    bubble.addEventListener("focusout", () => setTimeout(resume))
  },

  dismiss(bubble) {
    if (!bubble.isConnected || bubble.classList.contains("is-leaving")) return
    const gone = () => this.flip(() => bubble.remove())
    if (reduced()) return gone()
    bubble.classList.add("is-leaving")
    bubble.addEventListener("animationend", gone, {once: true})
  },

  // FLIP: the bubbles that stay slide from where they were to where they are now.
  flip(change) {
    const before = new Map([...this.box.children].map(b => [b, b.getBoundingClientRect().top]))
    change()
    if (reduced()) return
    for (const b of this.box.children) {
      if (!before.has(b)) continue
      const dy = before.get(b) - b.getBoundingClientRect().top
      if (dy) b.animate([{transform: `translateY(${dy}px)`}, {transform: "none"}], {duration: 250, easing: "ease-out"})
    }
  },

  // The topic's name in the sidebar glows; one already glowing for a moment is left alone.
  glow(topicId) {
    const started = this.glowing.get(topicId)
    if (started && Date.now() - started < 500) return
    this.glowing.set(topicId, Date.now())
    const name = this.topicName(topicId)
    if (!name) return
    name.classList.remove("sidebar-burn")
    name.style.animationDelay = ""
    void name.offsetWidth  // restarts the animation
    name.classList.add("sidebar-burn")
  },

  topicName(topicId) {
    return document.querySelector(`#sidebar .sidebar-topic[data-topic-id="${CSS.escape(topicId)}"] .sidebar-topic-name`)
  },

  // After a swap: names still glowing go on where they were, through the DOM (never a style
  // attribute in the markup: the content security policy refuses those).
  reglow() {
    for (const [topicId, started] of this.glowing) {
      const elapsed = Date.now() - started
      if (elapsed >= BURN_MS) { this.glowing.delete(topicId); continue }
      const name = this.topicName(topicId)
      if (!name) continue
      name.style.animationDelay = `-${elapsed}ms`
      name.classList.add("sidebar-burn")
    }
  },

  // The sidebar and the header's Unread link with its count, from /sidebar. Neither is
  // swapped while it has the focus.
  async refreshSidebar() {
    const aside = document.getElementById("sidebar")
    if (document.visibilityState !== "visible") return

    const url = new URL(this.el.dataset.sidebar, window.location.origin)
    if (aside?.dataset.category) url.searchParams.set("category", aside.dataset.category)
    if (aside?.dataset.topic) url.searchParams.set("topic", aside.dataset.topic)

    let html
    try {
      const response = await fetch(url, {credentials: "same-origin", headers: {accept: "text/html"}})
      if (!response.ok) return
      html = await response.text()
    } catch (_offline) {
      return
    }
    const doc = new DOMParser().parseFromString(html, "text/html")

    const link = document.getElementById("unread-link")
    const freshLink = doc.getElementById("unread-link")
    if (link && freshLink && !link.contains(document.activeElement)) link.replaceWith(freshLink)

    const nav = aside?.querySelector(".sidebar-nav")
    const fresh = doc.querySelector("#sidebar .sidebar-nav")
    if (!nav || !fresh || aside.contains(document.activeElement)) return
    // Groups and "more topics" stay open or folded as the reader left them.
    const open = new Map([...nav.querySelectorAll("details[id]")].map(d => [d.id, d.open]))
    nav.replaceChildren(...fresh.childNodes)
    nav.querySelectorAll("details[id]").forEach(d => { if (open.has(d.id)) d.open = open.get(d.id) })
    this.reglow()
  },
}
