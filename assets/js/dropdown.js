// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The app's dropdowns (CoreComponents.dropdown/1; steward decision, 2026-10-23): a <details>
// over a list of radio buttons, which works without scripts. With them: one open at a time;
// the list is placed by the window (fixed, so a scrolling table or a dialog does not clip
// it); its button shows the choice; a click on a choice, Enter or Escape closes it and gives
// the focus back to the button; a click elsewhere, scrolling or resizing closes it. The arrow
// keys move between choices as radio buttons do, and leave it open.

const MARGIN = 8

const openOnes = () => document.querySelectorAll("details[data-dropdown][open]")

const close = (dropdown, refocus) => {
  dropdown.open = false
  if (refocus) dropdown.querySelector("summary")?.focus()
}

const place = dropdown => {
  const menu = dropdown.querySelector(".dropdown-select-menu")
  const button = dropdown.querySelector("summary").getBoundingClientRect()
  dropdown.dataset.placed = ""
  // Set through the DOM, never a style attribute (SP-05).
  menu.style.minWidth = `${button.width}px`
  const {width, height} = menu.getBoundingClientRect()
  const below = button.bottom + 4
  const top = below + height > innerHeight - MARGIN && button.top - height - 4 > MARGIN
    ? button.top - height - 4
    : below
  menu.style.left = `${Math.max(MARGIN, Math.min(button.left, innerWidth - width - MARGIN))}px`
  menu.style.top = `${top}px`
}

// toggle does not bubble: listened to on the way down.
document.addEventListener("toggle", e => {
  const dropdown = e.target
  if (!(dropdown instanceof HTMLDetailsElement) || !dropdown.hasAttribute("data-dropdown")) return
  if (!dropdown.open) {
    delete dropdown.dataset.placed
    return
  }
  openOnes().forEach(other => { if (other !== dropdown) close(other, false) })
  place(dropdown)
  const chosen = dropdown.querySelector("input:checked") || dropdown.querySelector("input")
  chosen?.focus()
}, true)

let pointer = false
document.addEventListener("pointerdown", e => {
  pointer = true
  openOnes().forEach(dropdown => { if (!dropdown.contains(e.target)) close(dropdown, false) })
}, true)
document.addEventListener("keydown", () => { pointer = false }, true)

document.addEventListener("change", e => {
  const dropdown = e.target.closest?.("details[data-dropdown]")
  if (!dropdown || e.target.type !== "radio") return
  const label = e.target.closest("label")?.textContent.trim() ?? ""
  dropdown.querySelector(".dropdown-select-value").textContent = label
  const summary = dropdown.querySelector("summary")
  if (summary.hasAttribute("aria-label")) {
    summary.setAttribute("aria-label", summary.getAttribute("aria-label").replace(/: .*$/, `: ${label}`))
  }
  if (pointer) close(dropdown, true)
})

document.addEventListener("keydown", e => {
  const dropdown = e.target.closest?.("details[data-dropdown][open]")
  if (!dropdown) return
  if (e.key === "Escape" || (e.key === "Enter" && e.target.type === "radio")) {
    e.preventDefault()
    close(dropdown, true)
  }
})

const closeAll = () => openOnes().forEach(dropdown => close(dropdown, false))
window.addEventListener("resize", closeAll)
document.addEventListener("scroll", e => {
  // Scrolling the list itself keeps it open.
  if (e.target.closest?.(".dropdown-select-menu")) return
  closeAll()
}, {passive: true, capture: true})
