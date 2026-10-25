// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The account menu (Layouts.account_menu/1) is a <details>, so it opens and closes without
// scripts. With them (steward decision, 2026-10-23), a click or tap anywhere outside it
// closes it, and so does Escape, which gives the focus back to its button. A message's
// "React" choices (ReactionComponents.add_reaction/1) close the same way (steward decision,
// 2026-10-25).

const OUTSIDE_CLOSES = "#account-menu[open], .add-reaction[open]"

document.addEventListener("pointerdown", e => {
  document.querySelectorAll(OUTSIDE_CLOSES).forEach(el => {
    if (!el.contains(e.target)) el.open = false
  })
}, true)

document.addEventListener("keydown", e => {
  if (e.key !== "Escape") return
  document.querySelectorAll(OUTSIDE_CLOSES).forEach(el => {
    el.open = false
    el.querySelector("summary")?.focus()
  })
})
