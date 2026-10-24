// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The home page's "Unavailable" dialog (steward decision, 2026-10-24) is rendered open, so it
// shows without scripts; with them, it opens again as a modal: the page behind it is inert,
// Escape closes it and the focus starts on its button (AX-01).
const dialog = document.getElementById("topic-unavailable")
if (dialog?.open && dialog.showModal) {
  dialog.close()
  dialog.showModal()
  dialog.querySelector("button")?.focus()
}
