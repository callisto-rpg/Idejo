// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// AX-01: the Theme and Tutorial bubbles toggles say which choice is on (`aria-pressed`), as
// the stylesheet shows it. theme.js applies the choice to <html> before the buttons exist,
// so the state is read from there: on load, whenever those attributes change, after a live
// navigation and after the Notifier swaps in a fresh sidebar (`syncToggles`, from
// sidebar.js). The buttons keep it across patches (`JS.ignore_attributes`).
const root = document.documentElement

const pressed = (button) => {
  const theme = button.dataset.phxTheme
  if (theme === "system") return root.dataset.themeSource === "system"
  if (theme) return root.dataset.themeSource === "user" && root.dataset.theme === theme
  return button.dataset.choice === (root.dataset.bubbles || "on")
}

export function syncToggles() {
  for (const button of document.querySelectorAll(".theme-toggle button")) {
    button.setAttribute("aria-pressed", String(pressed(button)))
  }
}

new MutationObserver(syncToggles)
  .observe(root, {attributes: true, attributeFilter: ["data-theme", "data-theme-source", "data-bubbles"]})
window.addEventListener("phx:page-loading-stop", syncToggles)
syncToggles()
