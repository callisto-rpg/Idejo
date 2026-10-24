// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The header's button that hides and shows the categories sidebar. On wide screens the
// sidebar sits beside the page and the choice is remembered (theme.js applies it before
// the first paint); on narrow ones it opens over the page, for the moment only.
const root = document.documentElement
const wide = matchMedia("(min-width: 1024px)")
const toggle = () => document.getElementById("sidebar-toggle")

const isShown = () =>
  wide.matches ? root.dataset.sidebar !== "hidden" : root.dataset.drawer === "open"

const sync = () => toggle()?.setAttribute("aria-expanded", String(isShown()))

// The ×'s tutorial bubble on touch screens, which cannot point at it (steward decision,
// 2026-10-25): shown for 3 s, once a page, the first time the topic on screen's entry is in
// view (at load beside the page, or when the drawer opens), then fading out.
const PEEK_MS = 3000
let peeked = false

const peek = () => {
  if (peeked || !matchMedia("(hover: none)").matches || root.dataset.bubbles === "off" || !isShown()) return
  const bubble = document.querySelector("#sidebar .sidebar-topic.is-current .sidebar-unfollow-bubble")
  if (!bubble) return
  peeked = true
  bubble.classList.add("is-peek")
  setTimeout(() => bubble.classList.remove("is-peek"), PEEK_MS)
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
  try {
    localStorage.setItem(FOLDED, JSON.stringify([...ids]))
  } catch (_e) {
    // Storage refused (private window): folded for this page only.
  }
})

applyFolds()
