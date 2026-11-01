// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The topic menu (steward decision, 2026-10-23): a right click, the keyboard's menu key or a
// long press on a topic in a list or in the sidebar (`data-topic-menu`) opens
// `#topic-menu` (Layouts.topic_menu/1) at that place, with the topic's addresses filled in.
// Its items are plain forms, so the server does the rest; Copy link copies the topic's
// address. Arrow keys move between the items, Escape or a click elsewhere closes it and the
// focus goes back where it was.
//
// Owners and administrators (steward decision, 2026-11-01) also get `#topic-menu-admin`,
// filled in from `/topic-menu/{id}` once open: "N following", which a first click turns red
// as "Mark as inactive" and a second posts; Archive; "Move to…", which shows the categories
// (the topic's own left out); Delete, which a second click confirms.

const LONG_PRESS_MS = 500
// Where the arrow sits from the menu's left, and how far the menu stands from the point.
const ARROW_X = 16
const ARROW_GAP = 10
const MOVE_TOLERANCE = 10

const menu = () => document.getElementById("topic-menu")
// An item's words: never just "span", which is the icon (CoreComponents.icon/1).
const labelOf = button => button.querySelector(".topic-menu-label")
const items = el => Array.from(el.querySelectorAll("[role=menuitem]")).filter(i => i.offsetParent !== null)

let opener = null
let press = null

export function open(row, x, y) {
  const el = menu()
  if (!el) return false
  const id = row.dataset.topicMenu
  const path = row.dataset.topicPath

  el.querySelectorAll("form[data-action]").forEach(form => {
    form.action = `/t/${id}${form.dataset.action}`
  })
  // Following, as the sidebar knows: it lists every followed topic.
  const following = document.querySelector(`#sidebar [data-topic-id="${id}"][data-following]`)
  el.toggleAttribute("data-following", following !== null)
  el.dataset.path = path
  const link = labelOf(el.querySelector("#topic-menu-link"))
  link.textContent = link.dataset.label ||= link.textContent

  opener = document.activeElement
  el.hidden = false
  // Its arrow points at (x, y): under the point, or above it when there is no room below.
  // Kept inside the window; set through the DOM, never a style attribute (SP-05).
  const {width, height} = el.getBoundingClientRect()
  const left = Math.max(8, Math.min(x - ARROW_X, innerWidth - width - 8))
  const below = y + ARROW_GAP + height <= innerHeight - 8
  const top = below ? y + ARROW_GAP : Math.max(8, y - ARROW_GAP - height)
  el.style.left = `${left}px`
  el.style.top = `${top}px`
  el.style.setProperty("--arrow-x", `${Math.max(14, Math.min(x - left, width - 14))}px`)
  if (below) delete el.dataset.arrow
  else el.dataset.arrow = "bottom"
  items(el)[0]?.focus()
  fillAdmin(el, id)
  return true
}

// The administrators' items: hidden until the server says what they need.
function fillAdmin(el, id) {
  const admin = el.querySelector("#topic-menu-admin")
  if (!admin) return
  admin.hidden = true
  admin.dataset.topic = id
  admin.querySelectorAll("[data-armed]").forEach(disarm)
  showMove(admin, false)

  fetch(`/topic-menu/${encodeURIComponent(id)}`)
    .then(r => (r.ok ? r.json() : null))
    .then(info => {
      // Another topic's menu opened meanwhile, or the menu closed.
      if (!info || el.hidden || admin.dataset.topic !== id) return
      const following = admin.querySelector("#topic-menu-following")
      const text = labelOf(following)
      const count = (info.following === 1 ? following.dataset.one : following.dataset.many)
        .replace("%{count}", info.following)
      following.dataset.label = info.inactive ? `${count} · ${following.dataset.inactive}` : count
      text.textContent = following.dataset.label
      // Nothing to mark: inactive already, or inactive topics not allowed.
      following.toggleAttribute("data-final", info.inactive || !info.inactive_allowed)
      following.setAttribute("aria-disabled", String(info.inactive || !info.inactive_allowed))
      admin.querySelector("#topic-menu-archive").hidden = info.archived
      admin.querySelector("#topic-menu-move-toggle").hidden = info.archived
      admin.querySelectorAll("#topic-menu-move [data-category-id]").forEach(b => {
        b.hidden = b.dataset.categoryId === info.category_id
      })
      admin.hidden = false
    })
    .catch(() => {})
}


// A first click turns the item red with what a second click does.
function arm(button) {
  const span = labelOf(button)
  button.dataset.armed = span.textContent
  span.textContent = button.dataset.confirmLabel
}

function disarm(button) {
  labelOf(button).textContent = button.dataset.armed
  delete button.dataset.armed
}

function showMove(admin, shown) {
  admin.querySelector("#topic-menu-move").hidden = !shown
  admin.querySelector("#topic-menu-move-toggle").setAttribute("aria-expanded", String(shown))
}

export function close(refocus = true) {
  const el = menu()
  if (!el || el.hidden) return
  el.hidden = true
  if (refocus && opener && document.contains(opener)) opener.focus()
  opener = null
}

const rowOf = target => target.closest?.("[data-topic-menu]")

document.addEventListener("contextmenu", e => {
  const row = rowOf(e.target)
  if (!row || !menu()) return
  e.preventDefault()
  // From the keyboard there is no pointer: open by the row.
  const box = row.getBoundingClientRect()
  const keyboard = e.clientX === 0 && e.clientY === 0
  open(row, keyboard ? box.left + 16 : e.clientX, keyboard ? box.bottom : e.clientY)
})

// Long press on touch screens (iOS does not fire contextmenu for it).
document.addEventListener("touchstart", e => {
  const row = rowOf(e.target)
  if (!row || e.touches.length !== 1 || !menu()) return
  const {clientX: x, clientY: y} = e.touches[0]
  press = {x, y, timer: setTimeout(() => { press.opened = open(row, x, y) }, LONG_PRESS_MS)}
}, {passive: true})

document.addEventListener("touchmove", e => {
  if (!press) return
  const t = e.touches[0]
  if (Math.hypot(t.clientX - press.x, t.clientY - press.y) > MOVE_TOLERANCE) clearTimeout(press.timer)
}, {passive: true})

document.addEventListener("touchend", e => {
  if (!press) return
  clearTimeout(press.timer)
  // The press opened the menu: the finger lifting is not a tap on the link.
  if (press.opened) e.preventDefault()
  press = null
})

document.addEventListener("click", e => {
  const el = menu()
  if (!el || el.hidden) return
  const copy = e.target.closest("#topic-menu-link")
  const confirmable = e.target.closest("#topic-menu-admin button[data-confirm-label]")
  const moveToggle = e.target.closest("#topic-menu-move-toggle")
  if (copy) {
    copyLink(el, copy)
  } else if (confirmable) {
    if (confirmable.hasAttribute("data-final")) {
      e.preventDefault()
    } else if (!confirmable.hasAttribute("data-armed")) {
      e.preventDefault()
      arm(confirmable)
    }
    // Armed: the click posts its form.
  } else if (moveToggle) {
    const admin = el.querySelector("#topic-menu-admin")
    const shown = moveToggle.getAttribute("aria-expanded") !== "true"
    showMove(admin, shown)
    if (shown) items(admin.querySelector("#topic-menu-move"))[0]?.focus()
  } else if (!el.contains(e.target)) {
    close(false)
  }
})

function copyLink(el, button) {
  const url = new URL(el.dataset.path, location.origin).href
  const done = () => {
    labelOf(button).textContent = button.dataset.copied
    setTimeout(() => close(), 800)
  }
  if (navigator.clipboard) {
    navigator.clipboard.writeText(url).then(done, () => { prompt("", url); close() })
  } else {
    prompt("", url)
    close()
  }
}

document.addEventListener("keydown", e => {
  const el = menu()
  if (!el || el.hidden) return
  const list = items(el)
  const at = list.indexOf(document.activeElement)

  if (e.key === "Escape") {
    e.preventDefault()
    close()
  } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault()
    const step = e.key === "ArrowDown" ? 1 : -1
    list[(at + step + list.length) % list.length]?.focus()
  } else if (e.key === "Home" || e.key === "End") {
    e.preventDefault()
    list[e.key === "Home" ? 0 : list.length - 1]?.focus()
  } else if (e.key === "Tab") {
    close(false)
  }
})

// Scrolling or resizing moves the topic away from the menu.
window.addEventListener("resize", () => close(false))
document.addEventListener("scroll", () => close(false), {passive: true, capture: true})
