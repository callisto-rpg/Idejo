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

// Tutorial bubbles in the sidebar (steward decisions, 2026-10-25): the ×'s "close & unfollow
// thread" and a category's fold button's (its `data-bubble`, or `data-bubble-folded` while
// folded), at the right of what they explain, on hover or keyboard focus. One bubble on
// <body>, placed `fixed` from the button's position, so the sidebar's scrolling (or the
// drawer's) never clips it; hidden when anything scrolls. None in the drawer (narrow
// screens: the phone's sidebar; steward decision, 2026-10-25).
let floating = null
let shownFor = null

const bubbleFor = el =>
  el.getAttribute("aria-pressed") === "true" && el.dataset.bubbleFolded ? el.dataset.bubbleFolded : el.dataset.bubble

const showBubble = el => {
  if (!wide.matches) return
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

const bubbled = e => e.target.closest?.("#sidebar [data-bubble]")
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

// Wide touch screens cannot point: the ×'s bubble shows for 3 s, once a page, the first time
// the topic on screen's entry is in view beside the page, then fades out.
const PEEK_MS = 3000
let peeked = false

const peek = () => {
  if (peeked || !wide.matches || pointing.matches || root.dataset.bubbles === "off" || !isShown()) return
  const button = document.querySelector("#sidebar .sidebar-topic.is-current .sidebar-unfollow [data-bubble]")
  if (!button) return
  peeked = true
  setTimeout(() => {
    showBubble(button)
    setTimeout(() => { if (shownFor === button) hideBubble() }, PEEK_MS)
  }, 0)
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
// LiveView re-renders the header on navigation; keep the button's state right, and the
// sidebar's topics being unfollowed.
window.addEventListener("phx:page-loading-stop", () => {
  sync()
  showUnfollowing()
})
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
  // A fresh sidebar: the button a bubble pointed at is gone, and topics being unfollowed
  // show so again.
  hideBubble()
  showUnfollowing()
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

applyFolds()

// Unfollowing from the sidebar (steward decision, 2026-10-25): the × turns the topic's entry
// into "Topic unfollowed", in red, and a Cancel button for UNDO_MS; then the unfollow is sent
// (the form's own request, `quiet=1` so no message waits on the next page) and the entry
// goes. Leaving the page sends it at once. Without scripts the form posts as before.
const UNDO_MS = 4000
const unfollowing = new Map()

const topicEntries = id =>
  document.querySelectorAll(`#sidebar .sidebar-topic[data-topic-id="${CSS.escape(id)}"]`)

const markUnfollowing = (li, form) => {
  if (li.classList.contains("is-unfollowing")) return
  li.classList.add("is-unfollowing")
  const undo = document.createElement("span")
  undo.className = "sidebar-undo"
  const text = document.createElement("span")
  text.className = "sidebar-undo-text"
  text.setAttribute("role", "status")
  text.textContent = form.dataset.unfollowed || ""
  const cancel = document.createElement("button")
  cancel.type = "button"
  cancel.className = "sidebar-undo-cancel btn btn-xs"
  cancel.textContent = form.dataset.cancel || ""
  undo.append(text, cancel)
  li.appendChild(undo)
}

function showUnfollowing() {
  for (const id of unfollowing.keys()) {
    topicEntries(id).forEach(li => {
      const form = li.querySelector(".sidebar-unfollow")
      if (form) markUnfollowing(li, form)
    })
  }
}

const send = (entry, beacon) => {
  if (beacon && navigator.sendBeacon?.(entry.action, entry.data)) return
  fetch(entry.action, {method: "POST", body: entry.data, credentials: "same-origin", redirect: "manual"})
    .catch(() => {})
}

const unfollow = id => {
  const entry = unfollowing.get(id)
  if (!entry) return
  unfollowing.delete(id)
  send(entry, false)
  topicEntries(id).forEach(li => {
    // The focus, on Cancel, goes to the next entry or the category.
    if (li.contains(document.activeElement)) {
      const next = li.nextElementSibling || li.previousElementSibling
      const target = next?.querySelector("a") || li.closest(".sidebar-category")?.querySelector(".sidebar-link")
      target?.focus()
    }
    li.remove()
  })
}

document.addEventListener("submit", e => {
  const form = e.target.closest?.("#sidebar .sidebar-unfollow")
  if (!form) return
  e.preventDefault()
  const li = form.closest(".sidebar-topic")
  const id = li?.dataset.topicId
  if (!id || unfollowing.has(id)) return
  const data = new FormData(form)
  data.set("quiet", "1")
  unfollowing.set(id, {action: form.action, data, timer: setTimeout(() => unfollow(id), UNDO_MS)})
  hideBubble()
  const hadFocus = li.contains(document.activeElement)
  markUnfollowing(li, form)
  if (hadFocus) li.querySelector(".sidebar-undo-cancel")?.focus()
})

document.addEventListener("click", e => {
  const cancel = e.target.closest("#sidebar .sidebar-undo-cancel")
  if (!cancel) return
  const li = cancel.closest(".sidebar-topic")
  const id = li.dataset.topicId
  clearTimeout(unfollowing.get(id)?.timer)
  unfollowing.delete(id)
  topicEntries(id).forEach(entry => {
    entry.classList.remove("is-unfollowing")
    entry.querySelector(".sidebar-undo")?.remove()
  })
  li.querySelector(".sidebar-unfollow button")?.focus()
})

window.addEventListener("pagehide", () => {
  for (const [id, entry] of unfollowing) {
    clearTimeout(entry.timer)
    unfollowing.delete(id)
    send(entry, true)
  }
})
