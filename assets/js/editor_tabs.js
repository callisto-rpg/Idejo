// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// EditorTabs hook (AX-01): the message editor's Write / Preview tabs follow the ARIA tabs
// pattern. Only the selected tab is in the Tab order (the server sets tabindex); the arrow
// keys, Home and End select another tab and move the focus to it.
export const EditorTabs = {
  mounted() {
    this.el.addEventListener("keydown", e => {
      const tabs = [...this.el.querySelectorAll("[role=tab]")]
      const current = tabs.indexOf(document.activeElement)
      if (current < 0) return

      const next = {
        ArrowRight: (current + 1) % tabs.length,
        ArrowLeft: (current - 1 + tabs.length) % tabs.length,
        Home: 0,
        End: tabs.length - 1,
      }[e.key]
      if (next === undefined) return

      e.preventDefault()
      tabs[next].focus()
      tabs[next].click()
    })
  },
}
