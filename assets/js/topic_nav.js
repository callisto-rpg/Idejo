// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// TopicNav hook (steward decision, 2026-10-23), on TopicLive's #topic-nav: once the topic's
// title has scrolled under the header, a card at the right of the conversation with the
// title and links to the first message, the first unread, the last message and the reader's
// own last one. Where the right has no room for the card (phones, or the sidebar open on a
// narrow screen) it is a small pill at the top right that opens it. The state lives in data
// attributes the server never renders (JS.ignore_attributes).
//
// UnreadLine hook, on the "N unread messages" line: the page opens centred on the message
// below it, unless the address names a message (a permalink, TP-06), which TopicNav centres
// instead (a notification names the oldest unread one: `/m/{id}?unread`). The line fades by CSS
// after 4 s, then the server is told to drop it. With nothing unread, TopicNav opens the
// page at its end, where the conversation goes on (steward decision, 2026-10-24).
//
// Long topics load a window at a time (steward decision, 2026-11-01): a link to a message the
// page does not hold asks the server for the window around it (`jump`), which answers
// `scroll_to` once it is there; "N new messages" and "Jump to the end to write" answer
// `scroll_to_end`. The page opens at its end only when its window reaches the end
// (`data-at-end` on the topic), never on a page asked for (`?page=n`).

const CARD_REM = 15
const GAP_REM = 1

const reduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches
const rem = () => parseFloat(getComputedStyle(document.documentElement).fontSize)

// A message of a run of deleted ones is hidden for readers: the run's line stands for it.
const visible = el => {
  while (el.hidden && el.previousElementSibling) el = el.previousElementSibling
  return el
}

const scrollToMessage = (el, behavior) =>
  visible(el).scrollIntoView({block: "center", behavior: behavior || (reduced() ? "auto" : "smooth")})

export const TopicNav = {
  mounted() {
    this.pill = this.el.querySelector(".topic-nav-pill")
    this.layout = () => {
      cancelAnimationFrame(this.frame)
      this.frame = requestAnimationFrame(() => this.place())
    }
    window.addEventListener("scroll", this.layout, {passive: true})
    window.addEventListener("resize", this.layout)
    // The sidebar opening or closing moves the column.
    this.resize = new ResizeObserver(this.layout)
    const main = document.getElementById("main")
    if (main) this.resize.observe(main)

    this.pill.addEventListener("click", () => this.setOpen(!this.el.hasAttribute("data-open")))
    this.el.addEventListener("click", e => this.jump(e))
    this.onKey = e => {
      if (e.key === "Escape" && this.el.hasAttribute("data-open")) {
        this.setOpen(false)
        this.pill.focus()
      }
    }
    this.onOutside = e => {
      if (this.el.hasAttribute("data-open") && !this.el.contains(e.target)) this.setOpen(false)
    }
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("click", this.onOutside)
    this.handleEvent("scroll_to", ({id}) => {
      const target = document.getElementById(id)
      if (target) this.reach(target)
    })
    this.handleEvent("scroll_to_end", () =>
      requestAnimationFrame(() =>
        window.scrollTo({top: document.documentElement.scrollHeight, behavior: "auto"})))
    this.place()
    this.openAtNamed()
    this.openAtEnd()
  },

  updated() { this.place() },

  destroyed() {
    window.removeEventListener("scroll", this.layout)
    window.removeEventListener("resize", this.layout)
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("click", this.onOutside)
    this.resize.disconnect()
    cancelAnimationFrame(this.frame)
  },

  place() {
    const header = document.querySelector(".app-header")
    const top = header ? header.getBoundingClientRect().bottom : 0
    const title = document.querySelector("#main h1")
    const shown = title ? title.getBoundingClientRect().bottom < top : window.scrollY > 0
    const column = document.querySelector("#main > div")
    const free = column ? window.innerWidth - column.getBoundingClientRect().right : 0
    const mode = free >= (CARD_REM + 2 * GAP_REM) * rem() ? "card" : "pill"

    this.el.toggleAttribute("data-shown", shown)
    this.el.dataset.mode = mode
    if (!shown || mode === "card") this.setOpen(false)
  },

  // An address naming a message (a permalink, TP-06, or a notification's oldest unread):
  // centred once the page is laid out, rather than left to the browser's own jump, which
  // the page may land before (ShowAll collapsing bodies, the live view connecting).
  openAtNamed() {
    const target = /^#message-/.test(window.location.hash) &&
      document.getElementById(window.location.hash.slice(1))
    if (!target || placed.has(`named:${target.id}`)) return
    placed.add(`named:${target.id}`)
    requestAnimationFrame(() => scrollToMessage(target, "auto"))
  },

  // Once per page, as UnreadLine does: a reconnect mounts the hook again.
  openAtEnd() {
    const topic = this.el.closest("[data-topic-id]")
    const id = topic?.dataset.topicId
    if (placed.has(`end:${id}`) || window.location.hash || !topic?.hasAttribute("data-at-end")) return
    placed.add(`end:${id}`)
    requestAnimationFrame(() => {
      if (document.getElementById("unread-line")) return
      window.scrollTo({top: document.documentElement.scrollHeight, behavior: "auto"})
    })
  },

  setOpen(open) {
    this.el.toggleAttribute("data-open", open)
    this.pill.setAttribute("aria-expanded", String(open))
  },

  // Centred rather than under the header, and the focus goes along (AX-01): to the
  // message's first control, as the link it came from may be hidden now.
  jump(e) {
    const link = e.target.closest("a[href^='#message-']")
    if (!link) return
    e.preventDefault()
    history.replaceState(null, "", link.hash)
    this.setOpen(false)
    const target = document.getElementById(link.hash.slice(1))
    // Not in the window: the server loads the window around it, then `scroll_to`.
    if (target) this.reach(target)
    else this.pushEvent("jump", {id: link.hash.slice("#message-".length)})
  },

  reach(target) {
    scrollToMessage(target)
    visible(target).querySelector("a[href], button, textarea, [tabindex]")?.focus({preventScroll: true})
  },
}

// Scrolled to once per page: a reconnect mounts the hook again.
const placed = new Set()

export const UnreadLine = {
  mounted() {
    const id = this.el.dataset.messageId
    if (!placed.has(id) && !window.location.hash) {
      // After the other hooks (ShowAll collapses long bodies) have laid the page out.
      requestAnimationFrame(() => scrollToMessage(this.el.closest("li"), "auto"))
    }
    placed.add(id)
    this.el.addEventListener("animationend", () => this.pushEvent("unread_line_done", {}))
  },
}
