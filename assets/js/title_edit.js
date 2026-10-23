// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The topic title's pencil (steward decision, 2026-10-23) opens its form through `:target`,
// which works without scripts; with them, the title's text box also takes the focus (AX-01),
// and Escape or Cancel gives it back to the pencil.
document.addEventListener("click", e => {
  const link = e.target.closest("#rename-topic-link")
  if (link) {
    setTimeout(() => document.getElementById("rename-topic-title")?.select(), 0)
    return
  }
  if (e.target.closest("#rename-topic a[href='#']")) {
    setTimeout(() => document.getElementById("rename-topic-link")?.focus(), 0)
  }
})

document.addEventListener("keydown", e => {
  if (e.key !== "Escape" || !e.target.closest?.("#rename-topic")) return
  // Like Cancel: the form is no longer the target, so it hides.
  location.hash = ""
  document.getElementById("rename-topic-link")?.focus()
})
