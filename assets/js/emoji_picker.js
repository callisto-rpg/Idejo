// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// EmojiPicker hook (TP-17): the + reaction picker, drawn and searched in the browser. The
// list comes from /emoji-index.json (Idejo.Emoji.index_json/0) and the emoji from one sprite
// sheet (its "sprite"; steward decision, 2026-10-31), both kept by the browser for a year.
// Topic pages where the reader may react fetch both and build the buttons while the page is
// idle (`preloadEmoji`, from the `data-emoji-index` element), so the picker opens at once;
// the built groups move from one opening to the next. The server only hears the choice, as
// "react". The element is phx-update="ignore".

let loading = null  // the fetch, shared by every opening on the page
let groups = null   // the built groups: one element, moved into each opening
let choices = []    // each button with its names, for the search

const load = src => {
  loading ??= fetch(src, {credentials: "same-origin"}).then(response => {
    if (!response.ok) throw new Error(`emoji index: ${response.status}`)
    return response.json()
  })
  return loading
}

// One emoji's button: the same markup the reaction menu uses (add-reaction-choice). With the
// sprite sheet, the emoji is its cell (`cell`, counted in the index's order), placed through
// the DOM, never a style attribute (SP-05); without it, its own image.
const button = ([name, alt, src, others], sprite, cell) => {
  const el = document.createElement("button")
  el.type = "button"
  el.className = "add-reaction-choice"
  el.title = `:${name}:`
  el.setAttribute("aria-label", `:${name}:`)
  el.dataset.emoji = name
  if (sprite) {
    const span = document.createElement("span")
    span.className = "emoji emoji-sprite"
    span.style.setProperty("--x", cell % sprite.columns)
    span.style.setProperty("--y", Math.floor(cell / sprite.columns))
    el.append(span)
  } else {
    const img = document.createElement("img")
    img.src = src
    img.alt = alt
    img.className = "emoji"
    img.loading = "lazy"
    img.draggable = false
    el.append(img)
  }
  choices.push({el, names: [name, ...others]})
  return el
}

const build = ({categories, sprite}, labels) => {
  const root = document.createElement("div")
  root.className = "emoji-groups"
  root.dataset.groups = ""
  if (sprite) {
    root.style.setProperty("--emoji-sprite", `url("${sprite.src}")`)
    root.style.setProperty("--emoji-columns", sprite.columns)
    root.style.setProperty("--emoji-rows", sprite.rows)
  }
  let cell = 0
  for (const {key, emoji} of categories) {
    const section = document.createElement("section")
    section.setAttribute("aria-label", labels[key] || key)
    const title = document.createElement("h3")
    title.className = "emoji-group-title"
    title.textContent = labels[key] || key
    const grid = document.createElement("div")
    grid.className = "emoji-grid"
    grid.append(...emoji.map(entry => button(entry, sprite, cell++)))
    section.append(title, grid)
    root.append(section)
  }
  return root
}

// Fetches the list, warms the sprite sheet and builds the groups, once per page.
const prepare = (src, labels) =>
  load(src).then(index => {
    if (!groups) {
      groups = build(index, labels)
      if (index.sprite) new Image().src = index.sprite.src
    }
    return groups
  })

// Called when the page is idle: topic pages where the reader may react carry the list's
// address and the group names (TopicLive's `data-emoji-index`). Not on Save-Data.
export const preloadEmoji = () => {
  const el = document.querySelector("[data-emoji-index]")
  if (!el || navigator.connection?.saveData) return
  const idle = window.requestIdleCallback || (fn => setTimeout(fn, 1000))
  idle(() => prepare(el.dataset.emojiIndex, JSON.parse(el.dataset.emojiLabels)).catch(() => { loading = null }))
}

export const EmojiPicker = {
  mounted() {
    this.search = this.el.querySelector("#emoji-search")
    this.slot = this.el.querySelector("[data-groups]")
    this.groups = null
    this.status = this.el.querySelector("[data-status]")
    this.empty = this.el.querySelector("[data-empty]")
    this.failed = this.el.querySelector("[data-failed]")

    this.search.addEventListener("input", () => this.filter())
    this.onClick = event => {
      const choice = event.target.closest("button[data-emoji]")
      if (choice) this.pushEvent("react", {id: this.el.dataset.messageId, emoji: choice.dataset.emoji})
    }

    prepare(this.el.dataset.src, JSON.parse(this.el.dataset.labels))
      .then(built => {
        if (!this.el.isConnected) return
        built.addEventListener("click", this.onClick)
        this.slot.replaceWith(built)
        this.groups = built
        this.status.hidden = true
        this.filter()
      })
      .catch(() => {
        loading = null  // the next opening tries again
        this.status.hidden = true
        this.failed.hidden = false
      })
  },

  destroyed() {
    this.groups?.removeEventListener("click", this.onClick)
  },

  // Names containing the query (":joy:" and "joy" alike); groups with none are hidden.
  filter() {
    if (!this.groups) return
    const query = this.search.value.trim().toLowerCase().replace(/^:+|:+$/g, "")
    for (const {el, names} of choices) el.hidden = query !== "" && !names.some(name => name.includes(query))
    let any = false
    for (const section of this.groups.children) {
      const shown = section.querySelector("button[data-emoji]:not([hidden])") !== null
      section.hidden = !shown
      any ||= shown
    }
    this.empty.hidden = any || this.groups.children.length === 0
  },
}
