// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The graphical composer (TP-11; steward decision, 2026-11-02), for authors who turned on
// "Use the graphical composer": a bar under the box (#composer-toolbar, TopicLive's
// composer_toolbar/1) that the Composer hook mounts. At the left: an emoji (the + reaction
// picker, which then inserts `:name:`), an image (as !image, at the caret), the text controls
// (a new line, and Markdown around the selection) and + (the other commands: !spoiler,
// !poll, !schedule, !new-topic). At the right, Send: a click is Enter; a right click, a double click, a long
// press or the menu key opens its menu, pointing at it with a triangle: "Send" (Enter), "Send &
// new line" (Enter, the caret then on a new line) and "Send & start new message" (Ctrl+Enter,
// or ends an edit). Buttons never take the focus from the box when clicked, so the
// caret, the selection and a phone's keyboard stay.

import {InlineCard} from "./inline_cards"
import {mayStartNew} from "./composer_timer"

const LONG_PRESS_MS = 500

const WRAPS = {bold: ["**", "**"], italic: ["*", "*"], strike: ["~~", "~~"], code: ["`", "`"]}

// The edit a format makes to `value` with `start`..`end` selected: `{text, from, to, select}`,
// the text replacing from..to, and the selection after it (offsets into the new value).
export function formatEdit(action, value, start, end) {
  const selected = value.slice(start, end)
  if (action === "code" && selected.includes("\n")) {
    const lead = start === 0 || value[start - 1] === "\n" ? "" : "\n"
    const text = `${lead}\`\`\`\n${selected}\n\`\`\`\n`
    return {text, from: start, to: end, select: [start + lead.length + 4, start + lead.length + 4 + selected.length]}
  }
  // A line break at the caret, in place of the selection: Shift+Enter, nothing sent.
  if (action === "newline") return {text: "\n", from: start, to: end, select: [start + 1, start + 1]}
  if (WRAPS[action]) {
    const [open, close] = WRAPS[action]
    const text = open + selected + close
    return {text, from: start, to: end, select: [start + open.length, start + open.length + selected.length]}
  }
  if (action === "link") {
    // A selected address becomes the link's target; other words its text.
    const url = /^[a-z][a-z0-9+.-]*:\/\/\S+$/i.test(selected)
    const label = url ? "" : selected
    const target = url ? selected : "url"
    const text = `[${label}](${target})`
    // What is still to write: the address after words, else the words (the caret in []).
    const select = url || label === ""
      ? [start + 1, start + 1]
      : [start + label.length + 3, start + label.length + 3 + target.length]
    return {text, from: start, to: end, select}
  }
  // Lines: from the start of the first selected line to the end of the last.
  const from = value.lastIndexOf("\n", start - 1) + 1
  const stop = value.indexOf("\n", end)
  const to = stop === -1 ? value.length : stop
  const lines = value.slice(from, to).split("\n")
  const prefix = i => (action === "quote" ? "> " : action === "list" ? "- " : `${i + 1}. `)
  const text = lines.map((line, i) => prefix(i) + line).join("\n")
  return {text, from, to, select: [from + text.length, from + text.length]}
}

// `:name:` at the caret, or after the selection (never in its place), set apart from the
// words around it by spaces.
export function emojiEdit(name, value, _start, end) {
  const before = value.slice(0, end)
  const lead = before === "" || /\s$/.test(before) ? "" : " "
  const text = `${lead}:${name}: `
  return {text, from: end, to: end, select: [end + text.length, end + text.length]}
}

// Applies an edit through the browser's own typing (undo works, `input` fires and repaints),
// or by hand where that is not supported.
function apply(input, {text, from, to, select}) {
  input.focus()
  input.setSelectionRange(from, to)
  const typed = text !== "" && document.execCommand?.("insertText", false, text)
  if (!typed) {
    input.setRangeText(text, from, to, "end")
    input.dispatchEvent(new Event("input", {bubbles: true}))
  }
  input.setSelectionRange(select[0], select[1])
}

export function mountToolbar(hook) {
  const bar = document.getElementById("composer-toolbar")
  if (!bar) return () => {}
  const input = hook.input
  const send = bar.querySelector("#composer-send")
  const menu = bar.querySelector("#composer-send-menu")
  const item = bar.querySelector("#composer-send-new")
  const plain = bar.querySelector("#composer-send-plain")
  const line = bar.querySelector("#composer-send-line")
  const items = [plain, line, item]
  const editing = () => hook.el.hasAttribute("data-editing")
  bar.hidden = false

  const togglePanel = button => {
    const open = button.getAttribute("aria-expanded") !== "true"
    for (const other of bar.querySelectorAll("[data-panel]")) {
      other.setAttribute("aria-expanded", String(open && other === button))
      document.getElementById(other.dataset.panel).hidden = !(open && other === button)
    }
  }

  const closePanels = () => {
    for (const toggle of bar.querySelectorAll("[data-panel][aria-expanded=true]")) togglePanel(toggle)
  }

  // Ctrl+Enter commits at any time (steward request, 2026-11-09); before the timer line has
  // run out, it says that the next message waits for it.
  const ready = () => editing() || hook.sent === "" || mayStartNew()

  const openMenu = () => {
    item.textContent = editing() ? bar.dataset.labelEndEdit : ready() ? bar.dataset.labelNew : bar.dataset.labelTooSoon
    item.setAttribute("aria-disabled", "false")
    menu.hidden = false
    send.setAttribute("aria-expanded", "true")
    // From the keyboard, the focus goes into the menu; a click or a touch leaves it in the box.
    if (document.activeElement === send) plain.focus()
  }

  const closeMenu = (focusSend = false) => {
    if (menu.hidden) return
    menu.hidden = true
    send.setAttribute("aria-expanded", "false")
    if (focusSend) send.focus()
  }

  // Clicks keep the focus (and the selection) in the box.
  const onMouseDown = e => { if (e.target.closest("button")) e.preventDefault() }

  let pressTimer = null
  let pressed = false
  let pressAt = null
  const cancelPress = () => { clearTimeout(pressTimer); pressTimer = null }

  const onPointerDown = e => {
    if (!e.target.closest("#composer-send") || e.pointerType === "mouse") return
    pressed = false
    pressAt = [e.clientX, e.clientY]
    pressTimer = setTimeout(() => { pressed = true; openMenu() }, LONG_PRESS_MS)
  }
  const onPointerMove = e => {
    if (pressTimer && Math.hypot(e.clientX - pressAt[0], e.clientY - pressAt[1]) > 10) cancelPress()
  }

  const onClick = e => {
    const button = e.target.closest("button")
    if (!button) return
    if (button === send) {
      // The click that ends a long press only opened the menu.
      if (pressed) { pressed = false; return }
      closeMenu()
      hook.send(false)
    } else if (button === plain) {
      closeMenu()
      hook.send(false)
      input.focus()
    } else if (button === line) {
      closeMenu()
      // Sent, the caret goes on a new line; with nothing new to send, only the new line.
      if (!hook.send(false, undefined, {}, "\n")) {
        apply(input, formatEdit("newline", input.value, input.selectionStart, input.selectionEnd))
      }
      input.focus()
    } else if (button === item) {
      if (item.getAttribute("aria-disabled") === "true") return
      closeMenu()
      hook.send(true)
      input.focus()
    } else if (button.dataset.panel) {
      togglePanel(button)
    } else if (button.dataset.format) {
      apply(input, formatEdit(button.dataset.format, input.value, input.selectionStart, input.selectionEnd))
    } else if (button.dataset.command) {
      closePanels()
      hook.command(button.dataset.command)
    } else if (button.dataset.tool === "image") {
      hook.imageAtEnd = false
      document.querySelector("#composer-image-form input[type=file]")?.click()
    } else if (button.dataset.tool === "emoji") {
      // The picker gives the focus back to the box when it closes.
      InlineCard.opener = input
      hook.pushEvent("emoji_picker", {})
    }
  }

  const onContextMenu = e => {
    if (!e.target.closest("#composer-send")) return
    e.preventDefault()
    cancelPress()
    openMenu()
  }

  const onDoubleClick = e => { if (e.target.closest("#composer-send")) openMenu() }

  const onKeyDown = e => {
    if (menu.hidden) return
    if (e.key === "Escape") { e.preventDefault(); closeMenu(true); return }
    // Arrows, Home and End move between the menu's items.
    const at = items.indexOf(document.activeElement)
    if (at === -1) return
    const to = {ArrowDown: at + 1, ArrowUp: at - 1, Home: 0, End: items.length - 1}[e.key]
    if (to === undefined) return
    e.preventDefault()
    items[(to + items.length) % items.length].focus()
  }

  const onOutside = e => { if (!menu.hidden && !e.target.closest(".composer-send-wrap")) closeMenu() }

  const onEmoji = e => apply(input, emojiEdit(e.detail, input.value, input.selectionStart, input.selectionEnd))

  bar.addEventListener("mousedown", onMouseDown)
  bar.addEventListener("pointerdown", onPointerDown)
  bar.addEventListener("pointermove", onPointerMove)
  bar.addEventListener("pointerup", cancelPress)
  bar.addEventListener("pointercancel", cancelPress)
  bar.addEventListener("click", onClick)
  bar.addEventListener("contextmenu", onContextMenu)
  bar.addEventListener("dblclick", onDoubleClick)
  bar.addEventListener("keydown", onKeyDown)
  document.addEventListener("pointerdown", onOutside)
  window.addEventListener("idejo:emoji", onEmoji)

  return () => {
    cancelPress()
    document.removeEventListener("pointerdown", onOutside)
    window.removeEventListener("idejo:emoji", onEmoji)
  }
}
