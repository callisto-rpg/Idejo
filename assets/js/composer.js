// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Composer hook (M3): the text box is the author's open message (GM-02, GM-08, GM-10), or
// a closed message of theirs they chose to Edit (data-editing; steward decision, 2026-10-24):
// Enter saves it, Ctrl+Enter saves it and ends the edit, with no timer.
// Enter sends the whole text and keeps it in the box; a backdrop behind a transparent
// textarea draws sent text like any message's and highlights unsent text as temporary.
// Text just sent "burns" in: bright with a glow, fading into the message (BURN_MS).
// The backdrop also draws the caret, thicker than the browser's (whose own is transparent),
// and beside it, at the end of the text, a bubble (steward decision, 2026-10-25): "Enter to
// send" while something is not sent, then "Sent!" (white, turning to the theme's colours)
// with a faded "Continue typing to add to your message" until the author types again. The
// account menu and the Help page turn the bubbles off (theme.js).
//
// Commands (steward decision, 2026-10-23), listed after ! by `Suggest`: !image picks an image
// that lands at the end of the message; !new-topic sends, then goes to "New topic from this"
// with the message's text; !schedule asks the server's dialog for a delay and, once
// scheduled, takes the text not sent yet out of the box. !poll and !spoiler send what is new,
// then act on the message: the poll dialog opens, or the message is hidden as a spoiler (or
// shown again). `!spoiler:overlay text:` (steward decision, 2026-10-28), typed out, runs at
// its closing colon: the message is hidden with those words over it.
//
// Plugins (steward request, 2026-11-08; Idejo.Plugins): commands marked `plugin` in
// data-commands send what is new, then the server opens the plugin's dialog for the message
// (or, with nothing new, for the open message or a message of its own). Typed out,
// `!command:argument:` runs at its closing colon with the argument: a link (http or https)
// for plugins whose `argument` is "link", else words like a spoiler's. A `collapse` plugin
// (steward request, 2026-11-09) only puts its `!command ` in the text at the start of a line:
// the server folds the `:` lines under it when the message is stored.

// The same rule as the server's (Idejo.Messages): a `.` is added after text that does not end
// with punctuation, but never after or inside code, where it would become part of the code,
// nor when the author's "Automatic punctuation" is off (`punctuate` false, data-punctuate).
const ENDS_WITH_PUNCTUATION = /[.!?…:;,)\]}"'»”’]$/u
const FENCE = /^\s*(```|~~~)/

export function finishSentence(text, punctuate = true) {
  const body = text.replace(/\s+$/, "")
  if (body === "" || !punctuate || ENDS_WITH_PUNCTUATION.test(body)) return body
  const lines = body.split("\n")
  const last = lines[lines.length - 1]
  const fences = lines.filter(line => FENCE.test(line)).length
  if (fences % 2 === 1 || FENCE.test(last) || /^(    |\t)/.test(last)) return body
  return body + "."
}

// Splits `value` into runs of sent and unsent text. Characters kept from the
// sent text (a longest common subsequence) count as sent; everything typed or
// changed since counts as unsent, wherever the caret was.
export function sentRuns(sent, value) {
  let start = 0
  const max = Math.min(sent.length, value.length)
  while (start < max && sent[start] === value[start]) start++
  let end = 0
  while (end < max - start && sent[sent.length - 1 - end] === value[value.length - 1 - end]) end++

  const a = sent.slice(start, sent.length - end)
  const b = value.slice(start, value.length - end)
  const marks = new Array(b.length).fill(false)

  // Very large middles skip the table and count as unsent.
  if (a.length > 0 && b.length > 0 && a.length * b.length <= 4_000_000) {
    const w = b.length + 1
    const table = new Uint32Array((a.length + 1) * w)
    for (let i = a.length - 1; i >= 0; i--) {
      for (let j = b.length - 1; j >= 0; j--) {
        table[i * w + j] = a[i] === b[j]
          ? table[(i + 1) * w + j + 1] + 1
          : Math.max(table[(i + 1) * w + j], table[i * w + j + 1])
      }
    }
    for (let i = 0, j = 0; i < a.length && j < b.length;) {
      if (a[i] === b[j]) { marks[j] = true; i++; j++ }
      else if (table[(i + 1) * w + j] >= table[i * w + j + 1]) i++
      else j++
    }
  }

  const runs = [[value.slice(0, start), true]]
  for (let j = 0; j < b.length; j++) {
    const last = runs[runs.length - 1]
    if (last[1] === marks[j]) last[0] += b[j]
    else runs.push([b[j], marks[j]])
  }
  runs.push([value.slice(value.length - end), true])
  return runs
}

// TP-12: calls `send` with the image files pasted or dropped on `el`, instead of the
// browser's default; other pastes and drops are left alone.
export function onImages(el, send) {
  const images = list => Array.from(list || []).filter(f => f.type.startsWith("image/")).slice(0, 1)
  el.addEventListener("paste", e => {
    const files = images(e.clipboardData && e.clipboardData.files)
    if (files.length) { e.preventDefault(); send(files) }
  })
  el.addEventListener("dragover", e => {
    if (e.dataTransfer && Array.from(e.dataTransfer.types).includes("Files")) e.preventDefault()
  })
  el.addEventListener("drop", e => {
    const files = images(e.dataTransfer && e.dataTransfer.files)
    if (files.length) { e.preventDefault(); send(files) }
  })
}

// Adds `text` at the end of a text box, on a line of its own, and puts the caret after it.
// What is there stays as it is, so the sent text is still where the box starts.
export function appendLine(input, text) {
  const before = input.value
  input.value = before + (before === "" || before.endsWith("\n") ? "" : "\n") + text
  input.setSelectionRange(input.value.length, input.value.length)
}

// Inserts `text` at the caret of a text box, on a line of its own, and puts the caret after it.
export function insertAtCaret(input, text) {
  const start = input.selectionStart ?? input.value.length
  const end = input.selectionEnd ?? start
  const before = input.value.slice(0, start)
  const after = input.value.slice(end)
  const lead = before === "" || before.endsWith("\n") ? "" : "\n"
  const trail = after.startsWith("\n") ? "" : "\n"
  input.value = before + lead + text + trail + after
  const caret = (before + lead + text + trail).length
  input.setSelectionRange(caret, caret)
}

// What a reloaded page keeps of the text a browser put back in the box: only what followed
// the open message's text (`sent`, as the server holds it), which was typed and not sent.
// Anything else, the message itself included, would be shown twice.
export function keptAfterReload(value, sent) {
  if (sent === "" || value === "") return ""
  const start = sent + separatorAfter(sent)
  if (value.startsWith(start)) return value.slice(start.length)
  return value.startsWith(sent) ? value.slice(sent.length).replace(/^ /, "") : ""
}

// What follows sent text in the box: a space, so the next words continue its line, or a blank
// line after a quote (an inline reply), so they do not join the quote.
export function separatorAfter(body) {
  const last = body.slice(body.lastIndexOf("\n") + 1)
  return /^ {0,3}>/.test(last) ? "\n\n" : " "
}

// TP-08, an inline reply (steward decision, 2026-11-06): the quote's Markdown at the end of
// `value`, a block of its own, with a blank line after it for the answer.
export function quoteEdit(value, markdown) {
  const lead = value.trim() === "" ? "" : value.endsWith("\n\n") ? "" : value.endsWith("\n") ? "\n" : "\n\n"
  const text = lead + markdown + "\n\n"
  const end = value.length + text.length
  return {text, from: value.length, to: value.length, select: [end, end]}
}

import {Suggest} from "./suggest"
import {InlineCard} from "./inline_cards"
import {mayStartNew} from "./composer_timer"
import {mountToolbar} from "./composer_toolbar"
import {formatMarks, formatted} from "./composer_format"
import {Layout, render as renderView, sourceAt, pointAt} from "./composer_view"

// Where Ctrl+Enter keeps its own meaning (typing elsewhere, a link opening in a new tab), so
// it never reaches the composer from there.
const OWN_CTRL_ENTER = "input, textarea, select, [contenteditable], a[href], dialog[open]"

// How long text just sent glows before it reads like the rest (matches .composer-burn).
const BURN_MS = 2200
// How long the hint says the message is visible to all, after a send.
const VISIBLE_MS = 2000

// Enter three times in a row, nothing typed between and each within this of the last, works
// as Ctrl+Enter (steward decision, 2026-10-23), so phones, which have no Ctrl, can do it too.
// Room kept between the end of the box and the keyboard (or the bottom of the screen).
const REVEAL_MARGIN = 48

const ENTER_RUN = 3
// `!spoiler:overlay text:` just typed, at the start of a word: the whole of it, and the words.
export const SPOILER_LABEL = /(?:^|[\s(])(!spoiler:([^:\n]{1,100}):)$/
const ENTER_RUN_MS = 1000
// `!command:argument:` just typed: the whole of it, the command, and the argument (a link,
// whose own colons are part of it, or words without a colon).
export const PLUGIN_ARGUMENT = /(?:^|[\s(])(!([a-z0-9]+(?:-[a-z0-9]+)*):(https?:\/\/\S+?|[^:\n]{1,100}):)$/

// Marks, for each character of `after`, whether it is new since `before`: what a send burns.
export function burnMarks(before, after) {
  const marks = []
  for (const [text, kept] of sentRuns(before, after)) {
    for (const _ of text) marks.push(!kept)
  }
  return marks
}

const escape = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

const span = (cls, text) => text === "" ? "" : `<span class="${cls}">${escape(text)}</span>`

// The sent text as runs ([class, text]), the characters just sent marked to burn.
function burnRuns(sent, marks) {
  const runs = []
  let run = "", burning = null
  Array.from(sent).forEach((ch, i) => {
    const b = Boolean(marks[i])
    if (burning !== null && b !== burning) { runs.push([burning ? "composer-sent composer-burn" : "composer-sent", run]); run = "" }
    burning = b
    run += ch
  })
  if (run) runs.push([burning ? "composer-sent composer-burn" : "composer-sent", run])
  return runs
}

// An uploaded image's Markdown, as the composer inserts it (IdejoWeb.ImageUploads).
const IMAGE = /!\[[^\]\n]*\]\((\/uploads\/[A-Za-z0-9-]+\.(?:jpe?g|png|gif|webp))\)/g

// A GIF's Markdown (gif_picker.js): an image from one of the provider's hosts
// (`data-gif-hosts`), drawn as a "GIF:" pill like an uploaded image's.
export function gifPattern(hosts) {
  if (!hosts || hosts.length === 0) return null
  const escaped = hosts.map(h => h.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")
  return new RegExp(`!\\[[^\\]\\n]*\\]\\(((?:${escaped})/[^)\\s]+)\\)`, "g")
}

// Images in the box (steward decision, 2026-10-26): their Markdown stays in the text, so the
// backdrop keeps every character under the textarea, but drawn transparent
// (`composer-image`), with a pill ("image:" and the picture, like excerpts') over its start.
// Returns the runs split at each image, the pill as a run of no text and HTML of its own.
export function withImages(runs, value, label, gifs = null) {
  const images = Array.from(value.matchAll(IMAGE), m => [m.index, m.index + m[0].length, m[1], label])
  if (gifs?.pattern) {
    for (const m of value.matchAll(gifs.pattern)) images.push([m.index, m.index + m[0].length, m[1], gifs.label])
    images.sort((a, b) => a[0] - b[0])
  }
  if (images.length === 0) return runs
  const out = []
  let pos = 0
  for (const [cls, text] of runs) {
    let from = 0
    while (from < text.length) {
      const at = pos + from
      const image = images.find(([start, end]) => start <= at && at < end)
      const next = images.find(([start]) => start > at)
      if (image) {
        if (image[0] === at) out.push(["", "", pill(image[3], image[2])])
        const to = Math.min(text.length, image[1] - pos)
        out.push([`${cls} composer-image`, text.slice(from, to)])
        from = to
      } else {
        const to = next ? Math.min(text.length, next[0] - pos) : text.length
        out.push([cls, text.slice(from, to)])
        from = to
      }
    }
    pos += text.length
  }
  return out
}

const pill = (label, src) =>
  `<span class="composer-image-anchor"><span class="image-pill composer-image-pill">${escape(label)}<img src="${escape(src)}" alt="" class="image-pill-thumb"></span></span>`

// The runs as HTML, with `caret` (HTML) at character `at` of their text, when `at` is a number.
// A run with HTML of its own (a pill) is written as it is. `marks` (composer_format.js), when
// given, draws the live formatting inside each run's span.
export function withCaret(runs, at, caret, marks = null) {
  let html = "", pos = 0, placed = at == null
  const piece = (cls, text, start) =>
    text === "" ? "" : `<span class="${cls}">${formatted(text, start, marks)}</span>`
  for (const [cls, text, raw] of runs) {
    if (raw) {
      html += raw
    } else if (!placed && at <= pos + text.length) {
      html += piece(cls, text.slice(0, at - pos), pos) + caret + piece(cls, text.slice(at - pos), at)
      placed = true
    } else {
      html += piece(cls, text, pos)
    }
    pos += text.length
  }
  return placed ? html : html + caret
}

export const Composer = {
  mounted() {
    this.input = this.el.querySelector("textarea")
    this.backdrop = this.el.querySelector(".composer-backdrop")
    this.sent = ""
    // TP-11: the graphical composer shows the message as it will look (composer_view.js).
    this.graphical = this.el.hasAttribute("data-graphical") && this.el.dataset.graphical !== "false"
    this.pending = []
    if (this.graphical) this.el.classList.add("is-graphical")
    // A browser may put back what the box held before a reload, although it asks not to
    // (autocomplete="off"): that is the sent text again, not something typed. Only what
    // follows the sent text stays, as unsent.
    this.input.value = keptAfterReload(this.input.value, this.el.dataset.sent || "")
    // After a reload the author's open message is still theirs to continue (GM-12 grace).
    this.restore(this.el.dataset.sent || "")

    this.input.addEventListener("input", e => {
      this.enters = 0
      this.justSent = false
      this.typed = [this.input.value, this.input.selectionStart]
      this.typingCheck()
      if (e.inputType?.startsWith("insert") && (this.labelledSpoiler() || this.pluginArgument())) return
      this.paint()
    })
    // The caret drawn in the backdrop follows the focus and the selection.
    this.onSelection = () => {
      if (document.activeElement === this.input) {
        if (this.graphical && !this.composing) this.keepCaretOutOfMarkdown()
        this.paint()
      } else if (this.graphical) {
        this.followViewSelection()
      }
    }
    document.addEventListener("selectionchange", this.onSelection)
    for (const event of ["focus", "blur", "select", "keyup", "mouseup"]) {
      this.input.addEventListener(event, () => this.paint())
    }
    // TP-10: suggestions while typing an inline link; added first, so its Enter picks.
    this.suggest = new Suggest(this.input, this.el.querySelector("[role=listbox]"),
      (sign, q, reply) => this.pushEvent("suggest", {sign, q}, reply),
      {commands: JSON.parse(this.el.dataset.commands || "[]"), onCommand: name => this.command(name)})
    this.input.addEventListener("keydown", e => {
      if (e.key !== "Enter" || e.isComposing || e.shiftKey) return
      e.preventDefault()
      this.send(e.ctrlKey || e.metaKey || this.enterRun())
    })
    if (this.graphical) this.mountView()
    // Ctrl+Enter from anywhere else on the page (steward decision, 2026-10-25): starts a new
    // message when it may, sending what is not sent yet, and puts the caret at the end of the
    // box; when it may not yet, only the caret goes there, so the author goes on writing.
    this.onPageKey = e => {
      if (e.key !== "Enter" || !(e.ctrlKey || e.metaKey) || e.isComposing || e.defaultPrevented) return
      if (e.target === this.input || e.target.closest?.(OWN_CTRL_ENTER)) return
      if (document.querySelector("dialog[open]")) return
      e.preventDefault()
      if (this.sent !== "" && (this.el.hasAttribute("data-editing") || mayStartNew())) this.send(true)
      this.focusEnd()
    }
    document.addEventListener("keydown", this.onPageKey)
    // Appends to other messages above while the author types here (steward decision,
    // 2026-10-25): a bubble over the message counts them, until the author scrolls up.
    this.appended = new Set()
    this.appendedBox = document.getElementById("composer-appended")
    this.onAppended = e => {
      if (document.activeElement !== this.input || !this.appendedBox) return
      const message = e.detail.closest(".message-list > li")
      if (!message || message.contains(this.el)) return
      if (!(message.compareDocumentPosition(this.el) & Node.DOCUMENT_POSITION_FOLLOWING)) return
      this.appended.add(message.id)
      this.showAppended()
    }
    window.addEventListener("idejo:appended", this.onAppended)
    this.lastY = window.scrollY
    this.onScroll = () => {
      if (window.scrollY < this.lastY && this.appended.size > 0) this.fadeAppended()
      this.lastY = window.scrollY
    }
    window.addEventListener("scroll", this.onScroll, {passive: true})
    // The server says what it holds of the open message, e.g. after a reconnect.
    this.handleEvent("composer_sent", ({body, clear}) => {
      // A new message after Reply (steward decision, 2026-11-06): a blank box, whatever it held.
      if (clear) { this.input.value = ""; this.sent = ""; this.paint() } else this.restore(body)
    })
    // TP-08, Reply on a message above the one being written: its quote goes into it, inline.
    this.handleEvent("composer_quote", ({markdown}) => this.insertQuote(markdown))
    // Reply on a message below it: what is not sent yet joins it first, then the new message.
    this.handleEvent("composer_flush", ({id}) => {
      this.send(false)
      this.pushEvent("reply", {id, flushed: true})
    })
    // Edit (steward decision, 2026-10-24): the box takes the focus, the caret at the end.
    this.handleEvent("composer_focus", () => this.focusEnd())
    // TP-12: an image pasted or dropped here uploads; its Markdown comes back to the caret,
    // unsent, like anything typed.
    onImages(this.input, files => this.uploadImages(files))
    // A GIF chosen in the overlay: its Markdown at the caret, unsent, like an image.
    this.onGif = e => {
      insertAtCaret(this.input, e.detail.markdown)
      this.input.dispatchEvent(new Event("input", {bubbles: true}))
    }
    window.addEventListener("idejo:gif", this.onGif)
    this.handleEvent("image_uploaded", ({upload, markdown}) => {
      if (upload !== "composer_image") return
      this.dropPending()
      if (this.imageAtEnd) appendLine(this.input, markdown)
      else insertAtCaret(this.input, markdown)
      this.imageAtEnd = false
      this.paint()
    })
    // Refused or failed: the picture shown while it uploaded goes.
    this.handleEvent("image_failed", ({upload}) => {
      if (upload !== "composer_image") return
      this.dropPending()
      this.imageAtEnd = false
      this.paint()
    })
    // !schedule: the text it took is in a scheduled message now.
    this.handleEvent("composer_scheduled", () => {
      this.input.value = this.sent
      this.input.setSelectionRange(this.sent.length, this.sent.length)
      this.paint()
    })
    // TP-11: the graphical composer's buttons, for authors who chose it (steward decision,
    // 2026-11-02; assets/js/composer_toolbar.js).
    this.unmountToolbar = mountToolbar(this)
    this.paint()
  },

  destroyed() {
    this.unmountToolbar?.()
    this.unmountView?.()
    for (const {url} of this.pending) URL.revokeObjectURL(url)
    document.removeEventListener("selectionchange", this.onSelection)
    document.removeEventListener("keydown", this.onPageKey)
    window.removeEventListener("idejo:appended", this.onAppended)
    window.removeEventListener("scroll", this.onScroll)
    window.removeEventListener("idejo:gif", this.onGif)
  },

  // The provider's hosts, to draw GIFs' Markdown as pills; read once.
  gifs() {
    if (this.gifDrawing === undefined) {
      let hosts = []
      try { hosts = JSON.parse(this.el.dataset.gifHosts || "[]") } catch (_e) { hosts = [] }
      const pattern = gifPattern(hosts)
      this.gifDrawing = pattern && {pattern, label: this.el.dataset.labelGif || "GIF:"}
    }
    return this.gifDrawing
  },

  showAppended() {
    const box = this.appendedBox
    const n = this.appended.size
    const label = n === 1 ? box.dataset.labelOne : box.dataset.labelOther.replace("%{count}", n)
    let bubble = box.querySelector(".tutorial-bubble")
    if (!bubble) {
      bubble = document.createElement("span")
      bubble.className = "tutorial-bubble is-always points-up"
      bubble.addEventListener("animationend", e => {
        if (e.animationName !== "composer-appended-fade") return
        bubble.remove()
        this.appended.clear()
      })
      box.appendChild(bubble)
    }
    bubble.classList.remove("is-fading")
    bubble.textContent = label
  },

  // Scrolling up: the author is looking; the count fades out (2 s) and starts again.
  fadeAppended() {
    this.appendedBox?.querySelector(".tutorial-bubble")?.classList.add("is-fading")
  },

  // The caret at the end of the box, which takes the focus.
  focusEnd() {
    this.input.focus()
    this.input.setSelectionRange(this.input.value.length, this.input.value.length)
  },

  // `!spoiler:overlay text:` typed up to its closing colon: it leaves the text and runs.
  labelledSpoiler() {
    const caret = this.input.selectionStart
    if (caret !== this.input.selectionEnd) return false
    const match = SPOILER_LABEL.exec(this.input.value.slice(0, caret))
    if (!match || match[2].trim() === "") return false
    const start = caret - match[1].length
    const value = this.input.value
    this.input.value = value.slice(0, start) + value.slice(caret).replace(/^ /, "")
    this.input.setSelectionRange(start, start)
    this.paint()
    this.command("spoiler", match[2].trim())
    return true
  },

  // The patience timers start at a new message's first keystroke (steward request,
  // 2026-11-09): with nothing sent yet (not an edit), the server is told when text appears
  // in the box and when it is emptied again; it keeps the time on its own clock.
  typingCheck() {
    if (this.el.hasAttribute("data-editing") || this.sent !== "") return
    const typing = this.input.value.trim() !== ""
    if (typing === Boolean(this.typing)) return
    this.typing = typing
    this.pushEvent("composer_typing", {typing})
  },

  // A new connection is a new view: it knows nothing typed yet.
  reconnected() {
    this.typing = false
    this.typingCheck()
  },

  // `!command:argument:` of a plugin typed up to its closing colon: it leaves the text and
  // runs with the argument. Only for a plugin taking one, and a link only for a link.
  pluginArgument() {
    const caret = this.input.selectionStart
    if (caret !== this.input.selectionEnd) return false
    const match = PLUGIN_ARGUMENT.exec(this.input.value.slice(0, caret))
    if (!match) return false
    const plugin = this.plugin(match[2])
    const arg = match[3].trim()
    if (!plugin || arg === "" || plugin.argument === "none") return false
    if ((plugin.argument === "link") !== /^https?:\/\//.test(arg)) return false
    const start = caret - match[1].length
    const value = this.input.value
    this.input.value = value.slice(0, start) + value.slice(caret).replace(/^ /, "")
    this.input.setSelectionRange(start, start)
    this.paint()
    this.command(match[2], undefined, arg)
    return true
  },

  plugin(name) {
    const commands = JSON.parse(this.el.dataset.commands || "[]")
    return commands.find(command => command.plugin && command.name === name)
  },

  command(name, label, arg) {
    if (this.plugin(name)?.block === "collapse") {
      // Collapsible text (steward request, 2026-11-09): written in the message itself, so
      // its command goes back in, at the start of a line, for the title to follow.
      this.insertAtCaret(`!${name} `)
    } else if (this.plugin(name)) {
      // A plugin (steward request, 2026-11-08): its dialog gives the focus back to the box.
      InlineCard.opener = this.input
      const extra = arg ? {plugin: name, arg} : {plugin: name}
      if (this.unsent().trim() !== "") this.send(false, "plugin", extra)
      else this.pushEvent("open_plugin", {name, ...(arg ? {arg} : {})})
    } else if (name === "gif") {
      // GIFs (steward decision, 2026-11-03): the overlay (gif_picker.js) sends the chosen
      // one back as `idejo:gif`, and gives the focus back to the box.
      window.dispatchEvent(new CustomEvent("idejo:gif-open", {detail: {opener: this.input}}))
    } else if (name === "image") {
      this.imageAtEnd = true
      document.querySelector("#composer-image-form input[type=file]")?.click()
    } else if (name === "new-topic") {
      if (this.unsent().trim() !== "") this.send(false, "new_topic")
      else this.pushEvent("new_topic", {})
    } else if (name === "poll" || name === "spoiler") {
      // The poll dialog gives the focus back to the box when it closes.
      if (name === "poll") InlineCard.opener = this.input
      const extra = label ? {label} : {}
      if (this.unsent().trim() !== "") this.send(false, name, extra)
      else this.pushEvent(name === "poll" ? "open_poll" : "spoiler", extra)
    } else if (name === "forward") {
      // Forward (steward decision, 2026-11-02): the card for the message being replied to.
      this.pushEvent("forward_quoted", {})
    } else if (name === "schedule") {
      // The dialog gives the focus back to the box when it closes.
      InlineCard.opener = this.input
      this.pushEvent("open_schedule", {body: this.unsent().trim()})
    } else if (this.automessage(name)) {
      // An automessage (steward decision, 2026-11-01): the server posts it; what the
      // moderator wrote stays in the box.
      this.pushEvent("automessage", {name})
    }
  },

  automessage(name) {
    const commands = JSON.parse(this.el.dataset.commands || "[]")
    return commands.some(command => command.auto && command.name === name)
  },

  // What follows the sent text; nothing when sent text was changed (only an edit, not
  // something new to post).
  unsent() {
    const value = this.input.value
    return value.startsWith(this.sent) ? value.slice(this.sent.length) : ""
  },

  // Takes `body` as the sent text, keeping anything typed after it. An empty `body` means
  // nothing is open: the message closed while the author was away (GM-12), so what was sent
  // is in it already and leaves the box; only text typed since stays, unsent.
  restore(body) {
    // The usual reconnect: the server holds what the box already has; edits stay as they are.
    if (body !== "" && this.sent === body + separatorAfter(body)) return
    const old = this.sent
    const value = this.input.value
    const typed = old !== "" && value.startsWith(old) ? value.slice(old.length) : (old === "" ? value : "")
    const sent = body === "" ? "" : body + separatorAfter(body)
    this.input.value = sent + typed
    this.sent = sent
    this.paint()
  },

  // The quote's Markdown at the end of the box, unsent, through the browser's own typing (undo
  // works), the caret on the blank line after it.
  insertQuote(markdown) {
    const {text, from, to, select} = quoteEdit(this.input.value, markdown)
    this.input.focus()
    this.input.setSelectionRange(from, to)
    if (!document.execCommand?.("insertText", false, text)) {
      this.input.setRangeText(text, from, to, "end")
      this.input.dispatchEvent(new Event("input", {bubbles: true}))
    }
    this.input.setSelectionRange(select[0], select[1])
    this.paint()
    if (this.inView()) this.reveal()
  },

  // `text` at the caret, on a line of its own start, through the browser's own typing (undo
  // works), unsent.
  insertAtCaret(text) {
    const at = this.input.selectionStart
    const before = this.input.value.slice(0, at)
    const insert = before === "" || before.endsWith("\n") ? text : "\n" + text
    this.input.focus()
    if (!document.execCommand?.("insertText", false, insert)) {
      this.input.setRangeText(insert, at, this.input.selectionEnd, "end")
      this.input.dispatchEvent(new Event("input", {bubbles: true}))
    }
    this.paint()
  },

  // Counts Enters in a row; true at the third, which then starts the count again.
  enterRun() {
    const now = performance.now()
    this.enters = now - (this.lastEnter ?? -Infinity) <= ENTER_RUN_MS ? (this.enters || 0) + 1 : 1
    this.lastEnter = now
    if (this.enters < ENTER_RUN) return false
    this.enters = 0
    return true
  },

  // `then`: what the server does once it is stored ("new_topic", "poll" or "spoiler"), with
  // `extra` for it (the spoiler's `label`). `separator` follows the sent text: a new line after
  // Ctrl+Enter, else a space (a blank line after a quote), or a new line for the graphical
  // composer's "Send & new line".
  // True when something went to the server.
  send(isBreak, then, extra = {}, separator) {
    const caret = this.input.selectionStart
    const body = finishSentence(this.input.value, this.el.dataset.punctuate !== "false")
    separator ??= isBreak ? "\n" : separatorAfter(body)
    // Editing a message (steward decision, 2026-10-24): emptied, the server asks whether to
    // delete it.
    if (body === "" && this.el.hasAttribute("data-editing")) {
      if (this.sent !== "") this.pushEvent("commit", {body: "", break: isBreak})
      return this.sent !== ""
    }
    if (body === "") return false
    if (!isBreak && body === this.sent.replace(/\s+$/, "")) return false

    const before = this.sent
    // The new message's time went with this send; the next one starts again.
    this.typing = false
    // Seen when sent (steward decision, 2026-10-25): it stays in sight, unless the author had
    // scrolled away from it.
    const shown = this.inView()
    // Keep the caret where it was unless it was at the end of the text (GM-02).
    const atEnd = caret >= this.input.value.replace(/\s+$/, "").length
    this.input.value = body + separator
    this.sent = this.input.value
    this.justSent = true
    this.sentAt = performance.now()
    this.burn = {marks: burnMarks(before, this.sent), sent: this.sent, start: performance.now()}
    const position = atEnd ? this.input.value.length : caret
    this.input.setSelectionRange(position, position)
    this.paint()
    if (shown) this.reveal()

    this.pushEvent("commit", then ? {body, break: isBreak, then, ...extra} : {body, break: isBreak}, reply => {
      const typed = this.input.value.startsWith(this.sent) ? this.input.value.slice(this.sent.length) : ""

      if (reply.error) {
        // Not stored: what was sent counts as unsent again.
        this.sent = before
      } else if (reply.closed) {
        // Ctrl+Enter after the window: the message closed, and anything typed since starts
        // the next one (GM-05).
        this.input.value = typed
        this.sent = ""
        this.input.setSelectionRange(typed.length, typed.length)
      } else if (reply.body !== body) {
        // The server's text is the truth.
        this.input.value = reply.body + separator + typed
        this.sent = reply.body + separator
      }
      this.paint()
      // The page has the server's answer by now (the first Enter moves the box into the
      // message, under the author's name).
      if (shown) this.reveal()
    })
    return true
  },

  // TP-11, the graphical composer (steward decision, 2026-11-05; composer_view.js): the text
  // box keeps the Markdown, the caret and the keys, out of sight; the backdrop is the view
  // the author sees, clicks and taps. Its caret moves over hidden Markdown in one step,
  // Backspace and Delete take what is seen, Shift+Enter in a list starts its next item, and
  // a picture shows while it uploads.
  mountView() {
    const view = this.backdrop
    const on = (el, event, fn, opts) => { el.addEventListener(event, fn, opts); return () => el.removeEventListener(event, fn, opts) }
    const offs = [
      on(this.input, "compositionstart", () => { this.composing = true }),
      on(this.input, "compositionend", () => { this.composing = false }),
      on(this.input, "keydown", e => this.onViewKey(e)),
      on(view, "pointerdown", e => { this.pointerType = e.pointerType }),
      // The focus stays in the box: a tap keeps a phone's keyboard, and the mouse's caret and
      // selection are made here (a double click takes a word, a triple click a line).
      on(view, "mousedown", e => this.onViewMouseDown(e)),
      on(document, "mousemove", e => {
        if (this.dragAnchor == null || !(e.buttons & 1)) return
        const p = this.pointSource(e)
        if (p !== null) { this.selectRange(this.dragAnchor, p); this.paint() }
      }),
      on(document, "mouseup", () => { this.dragAnchor = null }),
      on(view, "mouseup", e => { if (this.pointerType !== "mouse") this.onViewPointer(e) }),
      // A picture chosen with the image button or !image shows while it uploads.
      on(document, "change", e => {
        if (e.target.matches?.("#composer-image-form input[type=file]")) this.addPending(e.target.files)
      }),
    ]
    onImages(view, files => this.uploadImages(files))
    this.unmountView = () => offs.forEach(off => off())
  },

  // The view's HTML, with the caret, the selection and the pictures still uploading.
  drawView(value, painted, caretAt) {
    const base = []
    for (const [cls, text] of painted) for (let k = 0; k < text.length; k++) base.push(cls)
    this.layout = new Layout(value, this.gifs()?.pattern || null)
    const {selectionStart: s, selectionEnd: e, selectionDirection: d} = this.input
    const select = document.activeElement === this.input && s !== e ? [s, e] : null
    return renderView(this.layout, {
      base,
      caret: caretAt == null ? null : [caretAt, this.caret(value, caretAt)],
      select,
      focus: select ? (d === "backward" ? s : e) : null,
      pending: this.pending,
      placeholder: this.input.placeholder,
    })
  },

  // The hidden box sits on the caret's line, so a browser scrolling to what is typed scrolls
  // there.
  placeInput() {
    const mark = this.backdrop.querySelector(".composer-caret, .g-focus")
    if (!mark) return
    const top = mark.getBoundingClientRect().top - this.el.getBoundingClientRect().top
    this.input.style.top = `${Math.max(0, top)}px`
  },

  // A caret moved inside hidden Markdown or a picture's (Home, End, Ctrl+arrows) goes where
  // it is drawn. Not where it was typed: after a closing `**` just typed, what follows is
  // plain.
  keepCaretOutOfMarkdown() {
    const {selectionStart: s, selectionEnd: e} = this.input
    if (s !== e || !this.layout || this.layout.value !== this.input.value) return
    if (this.typed && this.typed[0] === this.input.value && this.typed[1] === s) return
    const c = this.layout.canonical(s)
    if (c !== s) this.input.setSelectionRange(c, c)
  },

  // Words selected in the view (a long press on a phone) are the box's selection, for the
  // toolbar's buttons.
  followViewSelection() {
    const sel = window.getSelection()
    if (!sel || sel.isCollapsed || !this.backdrop.contains(sel.anchorNode) || !this.backdrop.contains(sel.focusNode)) return
    const a = sourceAt(this.backdrop, sel.anchorNode, sel.anchorOffset)
    const f = sourceAt(this.backdrop, sel.focusNode, sel.focusOffset)
    if (a === null || f === null || a === f) return
    this.input.setSelectionRange(Math.min(a, f), Math.max(a, f), f < a ? "backward" : "forward")
  },

  onViewMouseDown(e) {
    if (e.button !== 0) return
    if (this.pointerType !== "mouse") {
      if (document.activeElement === this.input) e.preventDefault()
      return
    }
    if (e.target.closest?.(".tutorial-bubble, .composer-hint")) return
    e.preventDefault()
    const layout = this.layout
    const p = this.pointSource(e) ?? this.input.value.length
    const {selectionStart: s, selectionEnd: t, selectionDirection: d} = this.input
    this.input.focus({preventScroll: true})
    this.goalX = null
    if (e.detail === 2 && layout) {
      const [a, b] = layout.wordAt(p)
      this.input.setSelectionRange(a, b)
    } else if (e.detail >= 3 && layout) {
      const line = layout.lines.find(l => l.a <= p && p <= l.b)
      if (line) this.input.setSelectionRange(line.a + line.prefix, line.b)
    } else if (e.shiftKey) {
      this.selectRange(d === "backward" ? t : s, p)
      this.dragAnchor = d === "backward" ? t : s
    } else {
      this.input.setSelectionRange(p, p)
      this.dragAnchor = p
    }
    this.paint()
  },

  // The place in the text under the pointer, where the caret goes; null outside the view.
  pointSource(e) {
    if (e.target.classList?.contains("g-image")) {
      const r = e.target.getBoundingClientRect()
      return Number(e.clientX < r.left + r.width / 2 ? e.target.dataset.a : e.target.dataset.b)
    }
    const hit = pointAt(e.clientX, e.clientY)
    const p = hit ? sourceAt(this.backdrop, hit[0], hit[1]) : null
    return p === null ? null : this.layout ? this.layout.canonical(p) : p
  },

  // A tap, or a selection made by a long press, in the view: the box takes the focus, with
  // the caret or the selection where it was made.
  onViewPointer(e) {
    if (e.button !== undefined && e.button !== 0) return
    if (e.target.closest?.(".tutorial-bubble, .composer-hint")) return
    const view = this.backdrop
    const length = this.input.value.length
    let start = null, end = null, direction = "forward"
    const sel = window.getSelection()
    if (sel && !sel.isCollapsed && view.contains(sel.anchorNode) && view.contains(sel.focusNode)) {
      const a = sourceAt(view, sel.anchorNode, sel.anchorOffset)
      const f = sourceAt(view, sel.focusNode, sel.focusOffset)
      if (a !== null && f !== null && a !== f) {
        start = Math.min(a, f)
        end = Math.max(a, f)
        direction = f < a ? "backward" : "forward"
      }
    }
    if (start === null) {
      let p = null
      if (e.target.classList?.contains("g-image")) p = Number(e.target.dataset.b)
      else {
        const hit = pointAt(e.clientX, e.clientY)
        p = hit ? sourceAt(view, hit[0], hit[1]) : null
      }
      p = this.layout ? this.layout.canonical(p ?? length) : (p ?? length)
      start = end = p
    }
    this.goalX = null
    this.input.focus({preventScroll: true})
    sel?.removeAllRanges()
    this.input.setSelectionRange(start, end, direction)
    this.paint()
  },

  onViewKey(e) {
    if (e.defaultPrevented || e.isComposing || this.composing || e.altKey) return
    const layout = this.layout
    if (!layout || layout.value !== this.input.value) return
    const input = this.input
    // A caret moved into hidden Markdown just before (Home, End) may not have been put where
    // it is drawn yet: the selection's event comes later.
    this.keepCaretOutOfMarkdown()
    const {selectionStart: s, selectionEnd: t, selectionDirection: d} = input
    const plain = !e.ctrlKey && !e.metaKey
    const anchor = d === "backward" ? t : s
    const focus = d === "backward" ? s : t

    if ((e.key === "ArrowRight" || e.key === "ArrowLeft") && plain) {
      e.preventDefault()
      const right = e.key === "ArrowRight"
      const step = p => (right ? layout.stepRight(p) : layout.stepLeft(p))
      if (e.shiftKey) this.selectRange(anchor, step(focus))
      else if (s !== t) input.setSelectionRange(right ? t : s, right ? t : s)
      else input.setSelectionRange(step(s), step(s))
      this.goalX = null
      this.paint()
    } else if ((e.key === "ArrowUp" || e.key === "ArrowDown") && plain) {
      e.preventDefault()
      const p = this.vertical(e.key === "ArrowUp" ? -1 : 1, focus)
      if (e.shiftKey) this.selectRange(anchor, p)
      else input.setSelectionRange(p, p)
      this.paint()
    } else if ((e.key === "Backspace" || e.key === "Delete") && plain && s === t) {
      e.preventDefault()
      const range = e.key === "Backspace" ? layout.backspace(s) : layout.forward(s)
      if (range) this.replaceText(range[0], range[1], "")
    } else if (e.key === "Enter" && e.shiftKey && plain && s === t) {
      // A new line in a list or a quote continues it; in an empty item, it ends the list.
      const line = layout.lines.find(l => l.a <= s && s <= l.b)
      if (!line || !["g-ul", "g-ol", "g-quote"].includes(line.cls)) return
      e.preventDefault()
      const prefix = input.value.slice(line.a, line.a + line.prefix)
      if (line.b === line.a + line.prefix) this.replaceText(line.a, line.b, "")
      else {
        const next = line.cls === "g-ol" ? prefix.replace(/\d+/, n => String(Number(n) + 1)) : prefix
        this.replaceText(s, s, "\n" + next)
      }
    }
  },

  // From `focus`, the place one line up (-1) or down (1) in the view, at the same distance from
  // the left as where the moves started; past the first or last line, the start or the end.
  vertical(dir, focus) {
    const layout = this.layout
    const mark = this.backdrop.querySelector(".composer-caret, .g-focus")
    if (mark) {
      const r = mark.getBoundingClientRect()
      if (this.goalX == null) this.goalX = r.left
      const view = this.backdrop.getBoundingClientRect()
      const band = this.visibleBand()
      const limit = dir < 0 ? Math.max(view.top, band.top) : Math.min(view.bottom, band.bottom)
      for (let y = dir < 0 ? r.top - 2 : r.bottom + 2; dir < 0 ? y > limit : y < limit; y += 4 * dir) {
        const hit = pointAt(this.goalX, y)
        const p = hit ? sourceAt(this.backdrop, hit[0], hit[1]) : null
        if (p === null) continue
        const range = document.createRange()
        try { range.setStart(hit[0], hit[1]) } catch (_e) { continue }
        const rect = range.getClientRects()[0] || hit[0].parentElement?.getBoundingClientRect()
        if (!rect || (dir < 0 ? rect.bottom <= r.top + 1 : rect.top >= r.bottom - 1)) return layout.canonical(p)
      }
    }
    // Off screen, or no drawing: the same column of the line before or after.
    const index = layout.lines.findIndex(l => l.a <= focus && focus <= l.b)
    const other = layout.lines[index + dir]
    if (!other) return dir < 0 ? 0 : this.input.value.length
    const column = focus - layout.lines[index].a
    return layout.canonical(Math.min(other.a + column, other.b))
  },

  selectRange(anchor, focus) {
    this.input.setSelectionRange(Math.min(anchor, focus), Math.max(anchor, focus), focus < anchor ? "backward" : "forward")
  },

  // Replaces from..to with `text` through the browser's own typing, so undo works.
  replaceText(from, to, text) {
    const input = this.input
    input.setSelectionRange(from, to)
    const done = text === "" ? document.execCommand?.("delete", false) : document.execCommand?.("insertText", false, text)
    if (!done) {
      input.setRangeText(text, from, to, "end")
      input.dispatchEvent(new Event("input", {bubbles: true}))
    }
  },

  // Pasted or dropped pictures upload; in the graphical composer they show at once.
  uploadImages(files) {
    if (this.graphical) this.addPending(files)
    this.upload("composer_image", files)
  },

  addPending(files) {
    if (!this.graphical) return
    const at = this.imageAtEnd ? this.input.value.length : (this.input.selectionStart ?? this.input.value.length)
    for (const file of Array.from(files || []).filter(f => f.type.startsWith("image/")).slice(0, 1)) {
      const entry = {at, url: URL.createObjectURL(file)}
      this.pending.push(entry)
      // Never left behind, should the server not answer.
      setTimeout(() => { if (this.pending.includes(entry)) { this.dropPending(entry); this.paint() } }, 120_000)
    }
    this.paint()
  },

  dropPending(entry = this.pending[0]) {
    if (!entry) return
    URL.revokeObjectURL(entry.url)
    this.pending = this.pending.filter(p => p !== entry)
  },

  paint() {
    const value = this.input.value
    const elapsed = this.burn ? performance.now() - this.burn.start : Infinity
    // A burn shows while it lasts and while the sent text is still the start of the box.
    const burning = elapsed < BURN_MS && this.burn.sent === this.sent && value.startsWith(this.sent)

    const painted = burning
      ? [...burnRuns(this.sent, this.burn.marks), ["composer-unsent", value.slice(this.sent.length)]]
      : sentRuns(this.sent, value).map(([text, sent]) => [sent ? "composer-sent" : "composer-unsent", text])
    const {selectionStart: start, selectionEnd: end} = this.input
    const caretAt = document.activeElement === this.input && start === end ? start : null

    // Nothing below may move while this repaints (steward report, 2026-10-25: the page shifted
    // up and down on phones as one typed and sent). The box keeps its height until it is
    // measured again, so the page never shrinks for a moment: scrolled to its end, the
    // browser would pull it up and leave it there. The scroll is put back in any case.
    const y = window.scrollY
    this.el.style.minHeight = `${this.el.offsetHeight}px`
    const surface = this.graphical ? this.backdrop : this.input
    const before = surface.offsetHeight
    if (this.graphical) {
      this.backdrop.innerHTML = this.drawView(value, painted, caretAt)
    } else {
      const runs = withImages(painted, value, this.el.dataset.labelImage || "image:", this.gifs())
      // TP-11: bold, italic, strikethrough and spoilers show while typing, markers kept.
      const marks = formatMarks(value)
      // The extra space keeps a trailing line break visible in the backdrop.
      this.backdrop.innerHTML = withCaret(runs, caretAt, caretAt == null ? "" : this.caret(value, caretAt), marks) + " "
    }
    this.fitHint()
    // "Sent!" turns from white to the theme's colours once, whatever repaints it.
    this.backdrop.querySelector(".is-sent")
      ?.style.setProperty("--sent-delay", `-${performance.now() - this.sentAt}ms`)
    // Repaints (every keystroke) keep the animation where it was: a negative delay, set
    // through the DOM, never a style attribute (SP-05).
    if (burning) {
      this.backdrop.querySelectorAll(".composer-burn").forEach(el => { el.style.animationDelay = `-${elapsed}ms` })
      clearTimeout(this.burnTimer)
      this.burnTimer = setTimeout(() => this.paint(), BURN_MS - elapsed + 50)
    }
    this.showStatus(value)
    const height = this.graphical ? before : this.input.offsetHeight
    const shown = caretAt != null && this.inView()
    if (this.graphical) {
      this.placeInput()
    } else {
      this.input.style.height = "auto"
      this.input.style.height = this.input.scrollHeight + "px"
    }
    this.el.style.minHeight = ""
    if (window.scrollY !== y) window.scrollTo(window.scrollX, y)
    // A new line while typing (steward decision, 2026-10-31): the page moves up by a line,
    // 1.5 em (the box's line height), and further if it would still be under the on-screen
    // keyboard, so what is being typed stays in sight on phones.
    if (shown && surface.offsetHeight > height) {
      window.scrollBy(0, 1.5 * (parseFloat(getComputedStyle(this.input).fontSize) || 16))
      this.reveal()
    }
  },

  // The bubble at the right of the author's name (steward decision, 2026-10-31): hidden
  // ("empty") until the author types, "unsent" until the message opens, then "sent", or
  // "sent, appends unsent" while something typed is not sent yet. None while editing.
  showStatus(value) {
    const el = document.getElementById("composer-status")
    if (!el) return
    const pending = value.replace(/\s+$/, "") !== this.sent.replace(/\s+$/, "")
    const status = this.sent !== "" ? (pending ? "appends" : "sent") : value.trim() === "" ? "empty" : "unsent"
    if (el.dataset.status === status) return
    el.dataset.status = status
    el.textContent = el.dataset[`label${status[0].toUpperCase()}${status.slice(1)}`] || ""
  },

  // The part of the page the reader sees: the visual viewport, without an on-screen keyboard.
  visibleBand() {
    const vv = window.visualViewport
    return vv ? {top: vv.offsetTop, bottom: vv.offsetTop + vv.height} : {top: 0, bottom: window.innerHeight}
  },

  inView() {
    const r = (this.graphical ? this.backdrop : this.input).getBoundingClientRect()
    const {top, bottom} = this.visibleBand()
    return r.bottom > top && r.top < bottom
  },

  // After a send the box can grow a line, or move down under the author's name (the first
  // Enter): scrolls just enough to keep its end above the keyboard.
  reveal() {
    const r = (this.graphical ? this.backdrop : this.input).getBoundingClientRect()
    const {bottom} = this.visibleBand()
    const below = r.bottom + REVEAL_MARGIN - bottom
    if (below > 0) window.scrollBy(0, below)
  },

  // The caret, and at the end of the text its bubble: "Enter to send" while something is not
  // sent, "Sent!" once it is, and the hint while nothing new was typed since.
  caret(value, at) {
    const labels = this.el.dataset
    const atEnd = value.slice(at).trim() === ""
    const pending = value.replace(/\s+$/, "") !== this.sent.replace(/\s+$/, "")
    let bubbles = ""
    if (atEnd && value.trim() !== "") {
      if (pending) bubbles = span("tutorial-bubble", labels.labelSend || "")
      else {
        if (this.justSent) bubbles = span("tutorial-bubble is-sent", labels.labelSent || "")
        bubbles += span("composer-hint", this.hintLabel())
      }
    }
    return `<span class="composer-caret">${bubbles && `<span class="composer-caret-bubbles">${bubbles}</span>`}</span>`
  },

  // The hint: "Message now visible to all!" for VISIBLE_MS after a send, then "Continue
  // typing to add to your message" (steward decision, 2026-10-25), repainted when it changes.
  hintLabel() {
    const labels = this.el.dataset
    const shown = this.justSent ? performance.now() - this.sentAt : Infinity
    if (shown >= VISIBLE_MS) return labels.labelContinue || ""
    clearTimeout(this.hintTimer)
    this.hintTimer = setTimeout(() => this.paint(), VISIBLE_MS - shown + 20)
    return labels.labelVisible || ""
  },

  // With no room for the hint beside the bubble (on a phone, or late on a line), it goes
  // below, moved left as far as it must to stay inside the composer, which grows to hold it.
  // The room it takes below is kept while the box has the focus, the largest it needed: the
  // hint comes and goes with every send and keystroke, and the page must not grow and shrink
  // with it. Given back when the box loses the focus.
  fitHint() {
    const hint = this.backdrop.querySelector(".composer-hint")
    const box = this.el.getBoundingClientRect()
    let room = 0
    if (hint && hint.getBoundingClientRect().right > box.right) {
      hint.classList.add("is-below")
      hint.style.maxWidth = `${box.width}px`
      const r = hint.getBoundingClientRect()
      if (r.right > box.right) hint.style.translate = `${Math.max(box.right - r.right, box.left - r.left)}px 0`
      // Measured from the box without the room it already keeps.
      const reserved = parseFloat(this.el.style.paddingBottom) || 0
      room = Math.max(0, r.bottom - (box.bottom - reserved)) + 4
    }
    const focused = document.activeElement === this.input
    this.hintRoom = focused ? Math.max(this.hintRoom || 0, room) : room
    this.el.style.paddingBottom = this.hintRoom ? `${this.hintRoom}px` : ""
  },
}
