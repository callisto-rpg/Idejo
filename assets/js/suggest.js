// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Suggestions while typing an inline link (TP-10; steward decision, 2026-10-22): after @, +,
// #, / or $ at the start of a word, the server suggests users, roles, topics, categories or
// tags, recent ones first, narrowed as the name is typed ("@rob" → robert, Robin). Picked with
// a click, or the arrow keys and Enter or Tab; Escape closes the list.
//
// After ! the composer lists its commands instead (steward decision, 2026-10-23): no server
// question, and picking one removes what was typed and runs it (`onCommand`). Enter picks one
// only once something follows the ! or an arrow chose it, so "Great !" and Enter still sends.
//
// The text box keeps the focus (ARIA combobox: aria-controls, aria-expanded,
// aria-activedescendant on it, a role="listbox" list beside it). Its keydown listener is
// added before the composer's, so Enter picks a suggestion instead of sending.

// A sign at the start of the text or after a space or "(", then what follows it.
export const TRIGGER = /(?:^|[\s(])([@+#/$!])([A-Za-z0-9_-]{0,40})$/

// What is being typed at the caret: {sign, query, start} (start: where the sign is), or null.
export function tokenAt(value, caret) {
  const match = TRIGGER.exec(value.slice(0, caret))
  if (!match) return null
  const [, sign, query] = match
  return {sign, query, start: caret - query.length - 1}
}

// The text with the token replaced by the sign, the pick and a space; and the caret after it.
export function applyPick(value, caret, token, insert) {
  const text = token.sign + insert + " "
  const after = value.slice(caret).replace(/^ /, "")
  return {value: value.slice(0, token.start) + text + after, caret: token.start + text.length}
}

const escape = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

export class Suggest {
  // `push(sign, query, reply)` asks the server; `reply` gets the items. `commands` ({name,
  // label, detail}) are offered after !, and `onCommand(name)` runs the one picked.
  constructor(input, list, push, {commands = null, onCommand = null} = {}) {
    this.input = input
    this.list = list
    this.push = push
    this.commands = commands
    this.onCommand = onCommand
    this.items = []
    this.active = -1
    this.token = null
    this.asked = 0
    this.timer = null

    input.setAttribute("aria-autocomplete", "list")
    input.setAttribute("aria-controls", list.id)
    input.setAttribute("aria-expanded", "false")

    input.addEventListener("input", () => this.update())
    input.addEventListener("click", () => this.update())
    input.addEventListener("blur", () => this.close())
    input.addEventListener("keydown", e => this.keydown(e))
    // A click on the list must not take the focus from the text box.
    list.addEventListener("mousedown", e => e.preventDefault())
    list.addEventListener("click", e => {
      const option = e.target.closest("[role=option]")
      if (option) this.pick(Number(option.dataset.index))
    })
  }

  update() {
    const token = tokenAt(this.input.value, this.input.selectionStart)
    if (!token) return this.close()
    if (token.sign === "!") return this.showCommands(token)
    this.token = token
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      const asked = ++this.asked
      this.push(token.sign, token.query, ({items}) => {
        // Only the latest question counts; the text may have moved on.
        if (asked === this.asked && this.token === token) this.show(items || [])
      })
    }, 120)
  }

  showCommands(token) {
    if (!this.commands) return this.close()
    const query = token.query.toLowerCase()
    const items = this.commands
      .filter(c => c.name.startsWith(query))
      .map(c => ({label: c.label, detail: c.detail, insert: c.name, command: true}))
    this.close()
    this.token = token
    this.show(items)
  }

  show(items) {
    this.items = items
    this.moved = false
    if (items.length === 0) return this.close()
    this.active = 0
    this.list.innerHTML = items.map((item, i) =>
      `<li role="option" id="${this.list.id}-${i}" data-index="${i}" class="suggestion">` +
      `<span class="suggestion-label">${escape(item.label)}</span>` +
      `<span class="suggestion-detail">${escape(item.detail)}</span></li>`
    ).join("")
    this.list.hidden = false
    this.input.setAttribute("aria-expanded", "true")
    this.highlight()
  }

  highlight() {
    this.list.querySelectorAll("[role=option]").forEach((option, i) => {
      option.setAttribute("aria-selected", String(i === this.active))
      if (i === this.active) option.scrollIntoView({block: "nearest"})
    })
    this.input.setAttribute("aria-activedescendant", `${this.list.id}-${this.active}`)
  }

  close() {
    clearTimeout(this.timer)
    this.asked++
    this.items = []
    this.active = -1
    this.token = null
    this.list.hidden = true
    this.list.innerHTML = ""
    this.input.setAttribute("aria-expanded", "false")
    this.input.removeAttribute("aria-activedescendant")
  }

  isOpen() { return this.items.length > 0 }

  keydown(e) {
    if (!this.isOpen() || e.isComposing) return
    const move = step => {
      this.active = (this.active + step + this.items.length) % this.items.length
      this.moved = true
      this.highlight()
    }
    const plainEnter = e.key === "Enter" && !e.shiftKey && !e.ctrlKey && !e.metaKey
    // A lone "!" then Enter: the list goes and the Enter is the composer's.
    if (plainEnter && this.token?.sign === "!" && this.token.query === "" && !this.moved) {
      this.close()
      return
    }
    if (e.key === "ArrowDown") move(1)
    else if (e.key === "ArrowUp") move(-1)
    else if (plainEnter || e.key === "Tab") this.pick(this.active)
    else if (e.key === "Escape") this.close()
    else return
    e.preventDefault()
    e.stopImmediatePropagation()
  }

  pick(index) {
    const item = this.items[index]
    if (!item || !this.token) return
    if (item.command) return this.runCommand(item.insert)
    const {value, caret} = applyPick(this.input.value, this.input.selectionStart, this.token, item.insert)
    this.close()
    this.input.value = value
    this.input.setSelectionRange(caret, caret)
    // The composer repaints and the editor's form sees the change.
    this.input.dispatchEvent(new Event("input", {bubbles: true}))
  }

  // What was typed for a command leaves the text; then the command runs.
  runCommand(name) {
    const value = this.input.value
    const caret = this.input.selectionStart
    const before = value.slice(0, this.token.start)
    const after = value.slice(caret).replace(/^ /, "")
    this.close()
    this.input.value = before + after
    this.input.setSelectionRange(before.length, before.length)
    this.input.dispatchEvent(new Event("input", {bubbles: true}))
    if (this.onCommand) this.onCommand(name)
  }
}

// The message editor's hook: the text box and the list sit in this element.
export const EditorSuggest = {
  mounted() {
    this.attach()
  },
  updated() {
    this.attach()
  },
  attach() {
    const input = this.el.querySelector("textarea")
    if (!input || input === this.input) return
    this.input = input
    const list = this.el.querySelector("[role=listbox]")
    this.suggest = new Suggest(input, list, (sign, q, reply) =>
      this.pushEvent("suggest", {sign, q}, reply))
  },
}
