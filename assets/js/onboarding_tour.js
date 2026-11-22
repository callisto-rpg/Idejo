// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The onboarding tour (steward request, 2026-11-22; IdejoWeb.OnboardingComponents). The
// server renders the step as a hidden #onboarding-tour: its card's text, what it points at
// (`data-target`, a selector) and where the card goes (`data-place`: right of it or above
// it). This draws it on <body>, out of any stacking context of the page:
//   - a hole over the target, whose huge shadow lays the page's background colour at 50%
//     over everything else, with a glowing outline round the hole;
//   - the card beside it, an arrow pointing at the target;
//   - every click, tap or press outside the target and the card stopped, the target's own
//     controls (a sidebar topic's ×) too.
// The sidebar's drawer opens on narrow screens when the target is in it. A step whose
// target is not on the page draws nothing and stops nothing. LiveView patches the element
// (the next step once a message is sent), so the page is watched for changes.

const root = document.documentElement
const PAD = 4
const GAP = 14

let shade = null
let card = null
let shown = null // {el, target, place, step}
let closedStep = null
let frame = null

const tourEl = () => document.getElementById("onboarding-tour")

const allowed = (node) => {
  if (!shown || !(node instanceof Node)) return true
  if (card?.contains(node)) return true
  return shown.target.contains(node) && !node.closest?.(".sidebar-topic-action")
}

// Clicks outside the target and the card do nothing while the tour shows: on window, in the
// capture phase, so before anything else hears them (LiveView's phx-click, sidebar.js).
const stop = (e) => {
  if (allowed(e.target)) return
  e.preventDefault()
  e.stopImmediatePropagation()
}
// Not touchstart: the page still scrolls under a finger.
for (const type of ["click", "pointerdown", "mousedown", "auxclick", "contextmenu", "submit"]) {
  window.addEventListener(type, stop, {capture: true, passive: false})
}
// The keyboard too: Tab stays on the target and the card; Enter elsewhere does nothing.
window.addEventListener("keydown", (e) => {
  if (!shown) return
  if (e.key === "Tab") {
    const stops = [shown.target, ...card.querySelectorAll("button")]
    const at = stops.indexOf(document.activeElement)
    e.preventDefault()
    const next = stops[(at + (e.shiftKey ? stops.length - 1 : 1) + stops.length) % stops.length]
    focusOn(next)
  } else if (!allowed(e.target)) {
    e.preventDefault()
    e.stopImmediatePropagation()
  }
}, {capture: true})

const focusOn = (el) => {
  const input = el.matches("textarea, input, a, button") ? el : el.querySelector("textarea, input, a, button")
  input?.focus({preventScroll: false})
}

const findTarget = (selector) => {
  let target = null
  try {
    target = document.querySelector(selector)
  } catch (_e) {
    return null
  }
  if (!target) return null
  if (target.closest("#sidebar")) {
    // Narrow screens: the sidebar is a drawer; open it. Folded categories and "more topics"
    // open too, so the link shows.
    if (!matchMedia("(min-width: 1024px)").matches) root.dataset.drawer = "open"
    target.closest(".sidebar-category")?.classList.remove("is-folded")
    const more = target.closest("details.sidebar-more")
    if (more) more.open = true
  }
  return target
}

const build = () => {
  shade = document.createElement("div")
  shade.className = "tour-shade"
  shade.setAttribute("aria-hidden", "true")
  card = document.createElement("div")
  card.className = "tour-card"
  card.setAttribute("role", "status")
  card.setAttribute("aria-live", "polite")
  card.addEventListener("click", (e) => {
    if (!e.target.closest("[data-tour-close]")) return
    closedStep = shown?.step
    hide()
  })
  document.body.append(shade, card)
}

const hide = () => {
  shown = null
  shade?.remove()
  card?.remove()
  shade = card = null
  root.classList.remove("is-touring")
  cancelAnimationFrame(frame)
}

const place = () => {
  if (!shown) return
  if (!shown.target.isConnected) {
    const again = findTarget(shown.el.dataset.target)
    if (!again) return hide()
    shown.target = again
  }
  const r = shown.target.getBoundingClientRect()
  Object.assign(shade.style, {
    left: `${r.left - PAD}px`,
    top: `${r.top - PAD}px`,
    width: `${r.width + 2 * PAD}px`,
    height: `${r.height + 2 * PAD}px`
  })

  const c = card.getBoundingClientRect()
  const vw = innerWidth
  const vh = innerHeight
  let where = shown.place
  // No room at the right (a phone): under the target instead.
  if (where === "right" && r.right + GAP + c.width > vw - 8) where = "below"
  let left
  let top
  if (where === "right") {
    left = r.right + GAP
    top = r.top + r.height / 2 - c.height / 2
  } else if (where === "below") {
    left = r.left + r.width / 2 - c.width / 2
    top = r.bottom + GAP
  } else {
    left = r.left + r.width / 2 - c.width / 2
    top = r.top - GAP - c.height
  }
  left = Math.max(8, Math.min(left, vw - c.width - 8))
  top = Math.max(8, Math.min(top, vh - c.height - 8))
  card.style.left = `${left}px`
  card.style.top = `${top}px`
  card.dataset.place = where
  // The arrow points at the target's middle, along the card's edge.
  const along = where === "right"
    ? r.top + r.height / 2 - top
    : r.left + r.width / 2 - left
  const max = (where === "right" ? c.height : c.width) - 16
  card.style.setProperty("--tour-arrow", `${Math.max(16, Math.min(along, max))}px`)
  frame = requestAnimationFrame(place)
}

const sync = () => {
  const el = tourEl()
  const step = el?.dataset.step
  if (!el || step === closedStep) {
    if (shown) hide()
    return
  }
  if (shown && shown.el === el && shown.step === step && shown.target.isConnected) return

  const target = findTarget(el.dataset.target)
  if (!target) {
    if (shown) hide()
    return
  }
  const fresh = !shown || shown.step !== step
  if (!shade) build()
  cancelAnimationFrame(frame)
  shown = {el, target, place: el.dataset.place, step}
  card.innerHTML = el.innerHTML
  card.dataset.step = step
  root.classList.add("is-touring")
  if (fresh) {
    target.scrollIntoView({block: "nearest"})
    focusOn(step === "4" ? card : target)
  }
  place()
}

new MutationObserver(sync).observe(document.documentElement, {
  childList: true,
  subtree: true,
  attributes: true,
  attributeFilter: ["data-step", "data-target"]
})
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", sync)
} else {
  sync()
}
