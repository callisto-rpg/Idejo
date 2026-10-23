// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The account menu (Layouts.account_menu/1) is a <details>, so it opens and closes without
// scripts. With them (steward decision, 2026-10-23), a click or tap anywhere outside it
// closes it, and so does Escape, which gives the focus back to its button.

const menu = () => document.getElementById("account-menu")

document.addEventListener("pointerdown", e => {
  const el = menu()
  if (el?.open && !el.contains(e.target)) el.open = false
}, true)

document.addEventListener("keydown", e => {
  const el = menu()
  if (e.key !== "Escape" || !el?.open) return
  el.open = false
  el.querySelector("summary")?.focus()
})
