// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// A message's actions on one line (steward request, 2026-11-09). When they do not all fit,
// the row gets `data-collapsed`: Reply, Forward and New Topic go behind "Quote", the
// moderators' actions behind "Moderate" (`.message-action-group`, drawn by the stylesheet).
// A group's button opens its menu (`data-open`, `aria-expanded`); a click outside, Escape or
// choosing an action closes it. Measured again when the row's width changes or the
// LiveView patches it. Without scripts nothing collapses: the row wraps as before.
//
// The pill of a touch screen (assets/js/message_actions.js, "Show message controls on mobile"
// off) must hold on one line, whatever the width (steward request, 2026-11-09): when it still
// overflows once collapsed, `data-compact="actions"` shows React, Edit, Delete and Report as
// their icons (their words stay for screen readers), then `data-compact="all"` the group
// buttons too. A group's menu opens under the pill, kept inside the screen (`data-align`).
// The row in place (that setting on, or a screen that points) is left as it was.

const rows = new Set()
let pending = false

// Whether the row's children, all of them in the row, take more than one line.
const wraps = row => {
  const items = [...row.children].flatMap(child =>
    child.classList.contains("message-action-group")
      ? [...child.querySelector(".message-action-group-items").children]
      : [child]
  ).filter(el => el.offsetParent !== null)
  if (items.length < 2) return false
  const top = items[0].offsetTop
  return items.some(el => Math.abs(el.offsetTop - top) > 2)
}

// The touch screens' pill: the only place the row is taken out of the flow.
const isPill = row => getComputedStyle(row).position === "absolute"

const overflows = row => row.scrollWidth > row.clientWidth + 1

const measure = row => {
  if (!row.isConnected) return
  // A group left open keeps the row as it is until it closes.
  if (row.querySelector(".message-action-group[data-open]")) return
  row.removeAttribute("data-collapsed")
  row.removeAttribute("data-compact")
  if (row.offsetParent === null || !wraps(row)) return
  row.setAttribute("data-collapsed", "")
  if (!isPill(row)) return
  for (const stage of ["actions", "all"]) {
    if (!overflows(row)) return
    row.setAttribute("data-compact", stage)
  }
}

// In the pill, a menu that would leave the screen on the right opens leftwards from its
// button's right edge instead.
const align = group => {
  group.removeAttribute("data-align")
  const row = group.closest(".message-actions")
  if (!row || !isPill(row)) return
  const items = group.querySelector(".message-action-group-items")
  if (items && items.getBoundingClientRect().right > document.documentElement.clientWidth - 8)
    group.setAttribute("data-align", "end")
}

const measureAll = () => {
  pending = false
  rows.forEach(measure)
}

const schedule = () => {
  if (pending) return
  pending = true
  requestAnimationFrame(measureAll)
}

const resizes = typeof ResizeObserver === "function" ? new ResizeObserver(schedule) : null

const closeGroup = (group, focus = false) => {
  if (!group?.hasAttribute("data-open")) return
  group.removeAttribute("data-open")
  group.removeAttribute("data-align")
  const toggle = group.querySelector(".message-action-group-toggle")
  toggle.setAttribute("aria-expanded", "false")
  if (focus) toggle.focus()
}

const openGroups = () => document.querySelectorAll(".message-action-group[data-open]")

document.addEventListener("click", e => {
  const toggle = e.target.closest?.(".message-action-group-toggle")
  if (toggle) {
    const group = toggle.closest(".message-action-group")
    const opening = !group.hasAttribute("data-open")
    openGroups().forEach(g => closeGroup(g))
    if (opening) {
      group.setAttribute("data-open", "")
      align(group)
      toggle.setAttribute("aria-expanded", "true")
      group.querySelector(".message-action-group-items")?.querySelector("a, button")?.focus()
    }
    return
  }
  // An action chosen, or a click anywhere else: the menu goes.
  openGroups().forEach(g => closeGroup(g))
})

document.addEventListener("keydown", e => {
  if (e.key !== "Escape") return
  const group = e.target.closest?.(".message-action-group[data-open]")
  if (group) closeGroup(group, true)
})

window.addEventListener("resize", schedule)

export const MessageActions = {
  mounted() {
    rows.add(this.el)
    resizes?.observe(this.el)
    schedule()
  },
  updated() { schedule() },
  destroyed() {
    rows.delete(this.el)
    resizes?.unobserve(this.el)
  },
}
