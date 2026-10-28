// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Who reacted (steward decision, 2026-10-28): a right click, the keyboard's menu key or a
// long press on a message's reactions (`.reactions`, ReactionComponents.reaction_bar/1) runs
// its `data-who` (a push of "reaction_who"); the server renders `#reaction-who`, and the
// `ReactionWho` hook puts it at that place, its arrow at the point, like the topic menu.
// Escape, a click elsewhere, a scroll or Tab closes it and the focus goes back. "Show more"
// turns it into a card (`#reaction-card`, the InlineCard hook), which gives the focus back
// in its turn.

import {InlineCard} from "./inline_cards"

const LONG_PRESS_MS = 500
const MOVE_TOLERANCE = 10
const ARROW_X = 16
const ARROW_GAP = 10

// Where the list was asked for, and what had the focus then.
let point = null
let press = null

function ask(bar, x, y) {
  if (!window.liveSocket || !bar.dataset.who) return false
  point = {x, y, opener: document.activeElement}
  window.liveSocket.execJS(bar, bar.dataset.who)
  return true
}

const barOf = target => target.closest?.(".reactions[data-who]")

document.addEventListener("contextmenu", e => {
  const bar = barOf(e.target)
  if (!bar) return
  e.preventDefault()
  // From the keyboard there is no pointer: open by the reaction that has the focus.
  const box = (e.target.closest(".reaction") || bar).getBoundingClientRect()
  const keyboard = e.clientX === 0 && e.clientY === 0
  ask(bar, keyboard ? box.left + 16 : e.clientX, keyboard ? box.bottom : e.clientY)
})

// Long press on touch screens (iOS does not fire contextmenu for it).
document.addEventListener("touchstart", e => {
  const bar = barOf(e.target)
  if (!bar || e.touches.length !== 1) return
  const {clientX: x, clientY: y} = e.touches[0]
  press = {x, y, timer: setTimeout(() => { press.opened = ask(bar, x, y) }, LONG_PRESS_MS)}
}, {passive: true})

document.addEventListener("touchmove", e => {
  if (!press) return
  const t = e.touches[0]
  if (Math.hypot(t.clientX - press.x, t.clientY - press.y) > MOVE_TOLERANCE) clearTimeout(press.timer)
}, {passive: true})

document.addEventListener("touchend", e => {
  if (!press) return
  clearTimeout(press.timer)
  // The press opened the list: the finger lifting does not toggle the reaction.
  if (press.opened) e.preventDefault()
  press = null
})

export const ReactionWho = {
  mounted() {
    // Its place comes from here, never from the server: patches keep it.
    this.js().ignoreAttributes(this.el, ["style", "data-arrow"])
    this.place()
    this.el.querySelector(".reaction-who-more")?.focus() || this.el.focus()

    this.onKey = e => {
      if (e.key === "Escape") { e.preventDefault(); this.close() }
      else if (e.key === "Tab") this.close(false)
    }
    this.onClick = e => {
      if (e.target.closest(".reaction-who-more")) InlineCard.opener = point?.opener
      else if (!this.el.contains(e.target)) this.close(false)
    }
    this.onScroll = () => this.close(false)
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("click", this.onClick)
    document.addEventListener("scroll", this.onScroll, {passive: true, capture: true})
    window.addEventListener("resize", this.onScroll)
  },

  // Another message's list, or the same one read again after a change.
  updated() {
    this.closing = false
    this.place()
  },

  destroyed() {
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("scroll", this.onScroll, {capture: true})
    window.removeEventListener("resize", this.onScroll)
  },

  close(refocus = true) {
    if (this.closing) return
    this.closing = true
    this.pushEvent("close_reaction_who", {})
    if (refocus && point?.opener && document.contains(point.opener)) point.opener.focus()
  },

  // Under the point, or above it when there is no room below; kept inside the window. Set
  // through the DOM, never a style attribute (SP-05).
  place() {
    if (!point) return
    const {x, y} = point
    const el = this.el
    const {width, height} = el.getBoundingClientRect()
    const left = Math.max(8, Math.min(x - ARROW_X, innerWidth - width - 8))
    const below = y + ARROW_GAP + height <= innerHeight - 8
    el.style.left = `${left}px`
    el.style.top = `${below ? y + ARROW_GAP : Math.max(8, y - ARROW_GAP - height)}px`
    el.style.setProperty("--arrow-x", `${Math.max(14, Math.min(x - left, width - 14))}px`)
    if (below) delete el.dataset.arrow
    else el.dataset.arrow = "bottom"
  },
}
