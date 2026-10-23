// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// EmojiPicker hook (TP-17): the + reaction picker, drawn and searched in the browser. The
// list comes from /emoji-index.json (Idejo.Emoji.index_json/0), fetched once per page and
// kept by the browser; the buttons are built once and cloned at each opening. The server
// only hears the choice, as "react". The element is phx-update="ignore".

let loading = null   // the fetch, shared by every opening on the page
let template = null  // the built groups, cloned at each opening

const load = src => {
  loading ??= fetch(src, {credentials: "same-origin"}).then(response => {
    if (!response.ok) throw new Error(`emoji index: ${response.status}`)
    return response.json()
  })
  return loading
}

// One emoji's button: the same markup the reaction menu uses (add-reaction-choice).
const button = ([name, alt, src, others]) => {
  const el = document.createElement("button")
  el.type = "button"
  el.className = "add-reaction-choice"
  el.title = `:${name}:`
  el.setAttribute("aria-label", `:${name}:`)
  el.dataset.emoji = name
  el.dataset.names = [name, ...others].join(" ")
  const img = document.createElement("img")
  img.src = src
  img.alt = alt
  img.className = "emoji"
  img.loading = "lazy"
  img.draggable = false
  el.append(img)
  return el
}

const build = (categories, labels) => {
  const fragment = document.createDocumentFragment()
  for (const {key, emoji} of categories) {
    const section = document.createElement("section")
    section.setAttribute("aria-label", labels[key] || key)
    const title = document.createElement("h3")
    title.className = "emoji-group-title"
    title.textContent = labels[key] || key
    const grid = document.createElement("div")
    grid.className = "emoji-grid"
    grid.append(...emoji.map(button))
    section.append(title, grid)
    fragment.append(section)
  }
  return fragment
}

export const EmojiPicker = {
  mounted() {
    this.search = this.el.querySelector("#emoji-search")
    this.groups = this.el.querySelector("[data-groups]")
    this.status = this.el.querySelector("[data-status]")
    this.empty = this.el.querySelector("[data-empty]")
    this.failed = this.el.querySelector("[data-failed]")

    this.search.addEventListener("input", () => this.filter())
    this.groups.addEventListener("click", event => {
      const choice = event.target.closest("button[data-emoji]")
      if (choice) this.pushEvent("react", {id: this.el.dataset.messageId, emoji: choice.dataset.emoji})
    })

    load(this.el.dataset.src)
      .then(({categories}) => {
        template ??= build(categories, JSON.parse(this.el.dataset.labels))
        this.groups.replaceChildren(template.cloneNode(true))
        this.status.hidden = true
        this.filter()
      })
      .catch(() => {
        loading = null  // the next opening tries again
        this.status.hidden = true
        this.failed.hidden = false
      })
  },

  // Names containing the query (":joy:" and "joy" alike); groups with none are hidden.
  filter() {
    const query = this.search.value.trim().toLowerCase().replace(/^:+|:+$/g, "")
    let any = false
    for (const section of this.groups.children) {
      let shown = false
      for (const choice of section.querySelectorAll("button[data-emoji]")) {
        const match = query === "" || choice.dataset.names.split(" ").some(name => name.includes(query))
        choice.hidden = !match
        shown ||= match
      }
      section.hidden = !shown
      any ||= shown
    }
    this.empty.hidden = any || this.groups.children.length === 0
  },
}
