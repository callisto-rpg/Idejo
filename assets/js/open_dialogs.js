// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Dialogs a page renders open (`data-show-modal`: the home page's "Unavailable" and visitors'
// cards, steward decisions, 2026-10-24) show without scripts; with them, each opens again as
// a modal: the page behind it is inert, Escape closes it and the focus starts on its first
// button (AX-01).
for (const dialog of document.querySelectorAll("dialog[data-show-modal][open]")) {
  if (!dialog.showModal) continue
  dialog.close()
  dialog.showModal()
  dialog.querySelector("button")?.focus()
}
