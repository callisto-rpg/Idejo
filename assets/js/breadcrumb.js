// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The header's breadcrumb on phones (steward decision, 2026-11-03): a topic title too long
// for the room left fades out at the right. Only the browser knows whether it is cut, so
// this marks its crumb with `data-cut` when it is; the stylesheet fades only those, so a
// title that fits is never dimmed. Without scripts the title ends in "…".
let observer = null

const measure = (crumb) => {
  const link = crumb.querySelector("a")
  if (!link) return
  crumb.toggleAttribute("data-cut", link.scrollWidth > link.clientWidth + 1)
}

const watch = () => {
  observer?.disconnect()
  const crumb = document.querySelector("#breadcrumb .header-crumb.is-last")
  if (!crumb) return
  observer = new ResizeObserver(() => measure(crumb))
  observer.observe(crumb)
  measure(crumb)
  // The title's font may arrive after the first measure.
  document.fonts?.ready.then(() => measure(crumb))
}

window.addEventListener("phx:page-loading-stop", watch)
watch()
