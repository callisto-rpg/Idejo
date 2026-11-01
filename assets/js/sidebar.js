// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

import {syncToggles} from "./toggles"

// The header's button that hides and shows the categories sidebar. On wide screens the
// sidebar sits beside the page and the choice is remembered (theme.js applies it before
// the first paint); on narrow ones it opens over the page, for the moment only.
const root = document.documentElement
const wide = matchMedia("(min-width: 1024px)")
const toggle = () => document.getElementById("sidebar-toggle")

const isShown = () =>
  wide.matches ? root.dataset.sidebar !== "hidden" : root.dataset.drawer === "open"

const sync = () => toggle()?.setAttribute("aria-expanded", String(isShown()))

// Tutorial bubbles in the sidebar (steward decisions, 2026-10-25): the ×'s "close & unfollow
// thread" and a category's fold button's (its `data-bubble`, or `data-bubble-folded` while
// folded), at the right of what they explain, on hover or keyboard focus. One bubble on
// <body>, placed `fixed` from the button's position, so the sidebar's scrolling (or the
// drawer's) never clips it; hidden when anything scrolls.
let floating = null
let shownFor = null

const bubbleFor = el =>
  el.getAttribute("aria-pressed") === "true" && el.dataset.bubbleFolded ? el.dataset.bubbleFolded : el.dataset.bubble

const showBubble = el => {
  if (!floating) {
    floating = document.createElement("span")
    floating.className = "tutorial-bubble sidebar-bubble"
    floating.setAttribute("aria-hidden", "true")
    document.body.appendChild(floating)
  }
  const r = el.getBoundingClientRect()
  floating.textContent = bubbleFor(el)
  floating.style.left = `${r.right + 8}px`
  floating.style.top = `${r.top + r.height / 2}px`
  floating.classList.add("is-shown")
  shownFor = el
}

const hideBubble = () => {
  floating?.classList.remove("is-shown")
  shownFor = null
}

// The links rolled into icons say their names in a bubble; shown in full, they need none.
const bubbled = e => {
  const el = e.target.closest?.("#sidebar [data-bubble]")
  if (el && el.closest(".sidebar-quicklinks-more") && root.dataset.quicklinks !== "rolled") return null
  return el
}
const pointing = matchMedia("(hover: hover)")

document.addEventListener("mouseover", e => {
  const el = bubbled(e)
  if (el && pointing.matches && el !== shownFor) showBubble(el)
})
document.addEventListener("mouseout", e => {
  const el = bubbled(e)
  if (el && el === shownFor && !el.contains(e.relatedTarget) && !el.matches(":focus-visible")) hideBubble()
})
document.addEventListener("focusin", e => {
  const el = bubbled(e)
  if (el && el.matches(":focus-visible")) showBubble(el)
})
document.addEventListener("focusout", e => { if (bubbled(e) === shownFor) hideBubble() })
document.addEventListener("scroll", () => { if (shownFor) hideBubble() }, {capture: true, passive: true})

// Touch screens cannot point: the ×'s bubble shows for 3 s, once a page, the first time the
// topic on screen's entry is in view (at load beside the page, or once the drawer has slid
// open), then fades out.
const PEEK_MS = 3000
const DRAWER_MS = 220
let peeked = false

const peek = () => {
  if (peeked || pointing.matches || root.dataset.bubbles || !isShown()) return
  const button = document.querySelector("#sidebar .sidebar-topic.is-current .sidebar-unfollow [data-bubble]")
  if (!button) return
  peeked = true
  setTimeout(() => {
    showBubble(button)
    setTimeout(() => { if (shownFor === button) hideBubble() }, PEEK_MS)
  }, wide.matches ? 0 : DRAWER_MS)
}

const closeDrawer = () => {
  delete root.dataset.drawer
  sync()
}

const flip = () => {
  if (wide.matches) {
    const hidden = root.dataset.sidebar !== "hidden"
    if (hidden) root.dataset.sidebar = "hidden"
    else delete root.dataset.sidebar
    try {
      if (hidden) localStorage.setItem("idejo:sidebar", "hidden")
      else localStorage.removeItem("idejo:sidebar")
    } catch (_e) {
      // Storage refused (private window): the choice lasts for this page only.
    }
  } else if (root.dataset.drawer === "open") {
    delete root.dataset.drawer
  } else {
    root.dataset.drawer = "open"
  }
  sync()
  peek()
}

document.addEventListener("click", (e) => {
  if (e.target.closest("#sidebar-toggle")) return flip()
  // A tap outside the open drawer closes it.
  if (root.dataset.drawer === "open" && !e.target.closest("#sidebar")) closeDrawer()
})

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && root.dataset.drawer === "open") {
    closeDrawer()
    toggle()?.focus()
  }
})

// Touch screens, narrow: swipe right to open the drawer, left to close it (steward decision,
// 2026-10-23). Only a quick, mostly sideways swipe counts, so scrolling never opens it; not
// from the screen's left edge (the system's "back" there), nor inside what scrolls sideways
// or takes text (code, tables, text boxes, the emoji picker).
const SWIPE_MIN = 60
const SWIPE_MAX_MS = 600
const EDGE = 20
const NO_SWIPE = "pre, table, input, textarea, select, [contenteditable], .emoji-groups, .suggestions"

// "open", "close" or null for a touch from (x0, y0) to (x1, y1) lasting `ms`.
export function swipe(x0, y0, x1, y1, ms) {
  const dx = x1 - x0
  const dy = y1 - y0
  if (ms > SWIPE_MAX_MS || Math.abs(dx) < SWIPE_MIN || Math.abs(dx) < 2 * Math.abs(dy)) return null
  if (dx > 0) return x0 < EDGE ? null : "open"
  return "close"
}

let touch = null

document.addEventListener("touchstart", e => {
  touch = null
  if (wide.matches || e.touches.length !== 1 || e.target.closest(NO_SWIPE)) return
  const t = e.touches[0]
  touch = {x: t.clientX, y: t.clientY, at: performance.now()}
}, {passive: true})

document.addEventListener("touchend", e => {
  if (!touch || wide.matches) return
  const t = e.changedTouches[0]
  const gesture = swipe(touch.x, touch.y, t.clientX, t.clientY, performance.now() - touch.at)
  touch = null
  const open = root.dataset.drawer === "open"
  if (gesture === "open" && !open) {
    root.dataset.drawer = "open"
    sync()
    peek()
  } else if (gesture === "close" && open) {
    closeDrawer()
  }
}, {passive: true})

document.addEventListener("touchcancel", () => { touch = null }, {passive: true})

wide.addEventListener("change", closeDrawer)
// LiveView re-renders the header on navigation; keep the button's state right.
window.addEventListener("phx:page-loading-stop", sync)
sync()
peek()

// Folded categories (steward decision, 2026-10-23): a category's button shows only its topics
// with something new (and the one on screen), remembered by the browser. Its topics past the
// first four are opened while it is folded, so the new ones among them show too. Applied
// again each time the Notifier hook swaps in a fresh sidebar.
const FOLDED = "idejo:folded-categories"

const foldedIds = () => {
  try {
    return new Set(JSON.parse(localStorage.getItem(FOLDED) || "[]"))
  } catch (_e) {
    return new Set()
  }
}

const setFolded = (category, folded) => {
  category.classList.toggle("is-folded", folded)
  category.querySelector(".sidebar-fold")?.setAttribute("aria-pressed", String(folded))
  const more = category.querySelector(".sidebar-more")
  if (more && folded) more.open = true
}

export function applyFolds() {
  // A fresh sidebar: the button a bubble pointed at is gone, and its theme toggle (shown to
  // visitors on phones) needs its state (AX-01).
  hideBubble()
  syncToggles()
  syncRoll()
  const ids = foldedIds()
  document.querySelectorAll("#sidebar .sidebar-category").forEach(category => {
    setFolded(category, ids.has(category.dataset.categoryId))
  })
}

document.addEventListener("click", (e) => {
  const button = e.target.closest(".sidebar-fold")
  if (!button) return
  const category = button.closest(".sidebar-category")
  const ids = foldedIds()
  const folded = !category.classList.contains("is-folded")
  if (folded) ids.add(category.dataset.categoryId)
  else ids.delete(category.dataset.categoryId)
  setFolded(category, folded)
  // Unfolded, past the first four go back behind "more topics".
  const more = category.querySelector(".sidebar-more")
  if (more && !folded) more.open = false
  // Its bubble says what a click does now.
  if (shownFor === button) showBubble(button)
  try {
    localStorage.setItem(FOLDED, JSON.stringify([...ids]))
  } catch (_e) {
    // Storage refused (private window): folded for this page only.
  }
})

// The links under All categories (steward decision, 2026-10-28): rolled up into their icons
// at its right, or shown in full. The choice lives on <html> (`data-quicklinks`), which
// theme.js sets before the first paint, so a fresh sidebar from the Notifier keeps it; the
// button only says which it is.
const ROLLED = "idejo:quicklinks"

const syncRoll = () =>
  document.getElementById("sidebar-quicklinks-roll")
    ?.setAttribute("aria-pressed", String(root.dataset.quicklinks === "rolled"))

document.addEventListener("click", (e) => {
  const button = e.target.closest("#sidebar-quicklinks-roll")
  if (!button) return
  const rolled = root.dataset.quicklinks !== "rolled"
  if (rolled) root.dataset.quicklinks = "rolled"
  else delete root.dataset.quicklinks
  syncRoll()
  if (shownFor && shownFor !== button) hideBubble()
  if (shownFor === button) showBubble(button)
  try {
    if (rolled) localStorage.setItem(ROLLED, "rolled")
    else localStorage.removeItem(ROLLED)
  } catch (_e) {
    // Storage refused (private window): rolled for this page only.
  }
})

applyFolds()
