// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// A message's actions (React, Edit, Reply…) on touch screens (steward decision, 2026-10-25):
// hidden until the message is tapped, then a pill under it (the stylesheet, `data-acting`),
// which any other action closes: a tap anywhere but on the pill (the same message again
// too), or a scroll. Screens that point show them on hover or focus, with no script.
// `data-acting` survives patches (`JS.ignore_attributes` on the message).

const touch = matchMedia("(hover: none)")
// Taps that do something of their own inside a message.
const OWN_TAP = "a, button, input, textarea, select, summary, label, details, dialog, [role=button], .reactions"
const SCROLL_CLOSES_PX = 12

let open = null
let openedAt = 0
let justClosed = null

const close = () => {
  open?.removeAttribute("data-acting")
  open = null
}

document.addEventListener("pointerdown", e => {
  justClosed = null
  if (!open || open.querySelector(".message-actions")?.contains(e.target)) return
  justClosed = open
  close()
}, true)

document.addEventListener("click", e => {
  if (!touch.matches) return
  const message = e.target.closest?.("#message-window article.message")
  if (!message || message === justClosed || e.target.closest(OWN_TAP)) return
  // "Show message controls on mobile" (steward decision, 2026-10-31): always in place.
  if (message.closest("[data-controls-mobile]")) return
  // Selecting text (a long press) is not asking for the actions.
  if (!document.getSelection()?.isCollapsed) return
  if (!message.querySelector(".message-actions > *")) return
  open = message
  openedAt = window.scrollY
  message.setAttribute("data-acting", "")
})

window.addEventListener("scroll", () => {
  if (open && Math.abs(window.scrollY - openedAt) > SCROLL_CLOSES_PX) close()
}, {passive: true})
