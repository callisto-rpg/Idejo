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
        // Each forum's logo at idejo's fixed address (`/logo`, 0.2.9), drawn like this
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

// The dot on the forum's logo (steward request, 2026-11-13; Layouts.community_menu/1): what is
// new in the topics the member follows in their other forums, asked of /community/activity
// (kept a minute by the server). White for new messages, red when one mentions them; the
// menu's name says so for screen readers. Asked again after each LiveView navigation, as a
// new page may bring a new header.
const showActivity = () => {
  const dot = document.getElementById("community-dot")
  if (!dot || dot.dataset.loaded) return
  dot.dataset.loaded = "true"
  const brand = document.getElementById("brand")
  const label = brand && brand.getAttribute("aria-label")

  fetch(dot.dataset.src, {credentials: "same-origin"})
    .then((response) => (response.ok ? response.json() : {}))
    .then(({unread, mentions}) => {
      const mention = Number.isInteger(mentions) && mentions > 0
      const fresh = mention || (Number.isInteger(unread) && unread > 0)
      dot.hidden = !fresh
      dot.classList.toggle("is-mention", mention)
      if (brand && label && fresh) {
        brand.setAttribute("aria-label", `${label}, ${mention ? dot.dataset.mention : dot.dataset.new}`)
      }
    })
    .catch(() => {})
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", showActivity)
} else {
  showActivity()
}
window.addEventListener("phx:page-loading-stop", showActivity)
