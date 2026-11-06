// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The community menu (steward decision, 2026-11-06; Layouts.community_menu/1): the forum's
// icon opens a <details>. The first time it opens, the member's other communities are asked
// of /community (Idejo.Community) and listed, each a link; none, the list stays hidden. A
// click outside or Escape closes it (account_menu.js).

const load = (list) => {
  if (list.dataset.loaded) return
  list.dataset.loaded = "true"

  fetch(list.dataset.src, {headers: {accept: "application/json"}, credentials: "same-origin"})
    .then((response) => (response.ok ? response.json() : {communities: []}))
    .then(({communities}) => {
      for (const {name, url} of communities || []) {
        const item = document.createElement("li")
        const link = document.createElement("a")
        link.href = url
        link.textContent = name
        item.append(link)
        list.append(item)
      }
      list.hidden = list.children.length === 0
    })
    .catch(() => {})
}

document.addEventListener("toggle", (e) => {
  const menu = e.target
  if (menu.id !== "community-menu" || !menu.open) return
  const list = menu.querySelector("#community-list")
  if (list) load(list)
}, true)
