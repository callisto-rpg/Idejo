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

wide.addEventListener("change", closeDrawer)
// LiveView re-renders the header on navigation; keep the button's state right.
window.addEventListener("phx:page-loading-stop", sync)
sync()
