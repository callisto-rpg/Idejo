// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The community menu (steward decision, 2026-11-06; Layouts.community_menu/1): the forum's
// icon opens a <details>. The first time it opens, the member's other communities are asked
// of /community (Idejo.Community) and listed, each a link; none, the list stays hidden. A
// click outside or Escape closes it (account_menu.js).

// Whether an address is a secure web address (a malformed one is not).
const secure = (url) => {
  try {
    return new URL(url).protocol === "https:"
  } catch {
    return false
  }
}

const load = (list) => {
  if (list.dataset.loaded) return
  list.dataset.loaded = "true"

  fetch(list.dataset.src, {credentials: "same-origin"})
    .then((response) => (response.ok ? response.json() : {communities: []}))
    .then(({communities}) => {
      for (const {name, url} of communities || []) {
        const item = document.createElement("li")
        const link = document.createElement("a")
        link.href = url
        // Each forum's logo at Idejo's fixed address (`/logo`, 0.2.9), drawn like this
        // forum's; a forum that has none to give (older) shows its name alone.
        if (secure(url)) {
          const logo = document.createElement("img")
          logo.src = new URL("logo", url).href
          logo.alt = ""
          logo.width = 20
          logo.height = 20
          logo.loading = "lazy"
          logo.className = "community-mark"
          logo.addEventListener("error", () => logo.remove())
          link.append(logo)
        }
        const label = document.createElement("span")
        label.textContent = name
        link.append(label)
        item.append(link)
        list.append(item)
      }
      list.hidden = list.children.length === 0
    })
    .catch(() => {})
}

// "Show the sidebar", the menu's first item on narrow screens (sidebar.js opens the drawer):
// the menu closes too.
document.addEventListener("click", (e) => {
  if (e.target.closest("#community-menu #sidebar-show")) {
    document.getElementById("community-menu").open = false
  }
})

document.addEventListener("toggle", (e) => {
  const menu = e.target
  if (menu.id !== "community-menu" || !menu.open) return
  const list = menu.querySelector("#community-list")
  if (list) load(list)
}, true)
