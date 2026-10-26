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
// shown again).

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
  const start = sent + " "
  if (value.startsWith(start)) return value.slice(start.length)
  return value.startsWith(sent) ? value.slice(sent.length).replace(/^ /, "") : ""
}

import {Suggest} from "./suggest"
import {InlineCard} from "./inline_cards"
import {mayStartNew} from "./composer_timer"

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
const ENTER_RUN_MS = 1000

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

// Images in the box (steward decision, 2026-10-26): their Markdown stays in the text, so the
// backdrop keeps every character under the textarea, but drawn transparent
// (`composer-image`), with a pill ("image:" and the picture, like excerpts') over its start.
// Returns the runs split at each image, the pill as a run of no text and HTML of its own.
export function withImages(runs, value, label) {
  const images = Array.from(value.matchAll(IMAGE), m => [m.index, m.index + m[0].length, m[1]])
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
        if (image[0] === at) out.push(["", "", pill(label, image[2])])
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
// A run with HTML of its own (a pill) is written as it is.
export function withCaret(runs, at, caret) {
  let html = "", pos = 0, placed = at == null
  for (const [cls, text, raw] of runs) {
    if (raw) {
      html += raw
    } else if (!placed && at <= pos + text.length) {
      html += span(cls, text.slice(0, at - pos)) + caret + span(cls, text.slice(at - pos))
      placed = true
    } else {
      html += span(cls, text)
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
    // A browser may put back what the box held before a reload, although it asks not to
    // (autocomplete="off"): that is the sent text again, not something typed. Only what
    // follows the sent text stays, as unsent.
    this.input.value = keptAfterReload(this.input.value, this.el.dataset.sent || "")
    // After a reload the author's open message is still theirs to continue (GM-12 grace).
    this.restore(this.el.dataset.sent || "")

    this.input.addEventListener("input", () => {
      this.enters = 0
      this.justSent = false
      this.paint()
    })
    // The caret drawn in the backdrop follows the focus and the selection.
    this.onSelection = () => { if (document.activeElement === this.input) this.paint() }
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
      const message = e.detail.closest("#messages > li")
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
    this.handleEvent("composer_sent", ({body}) => this.restore(body))
    // Edit (steward decision, 2026-10-24): the box takes the focus, the caret at the end.
    this.handleEvent("composer_focus", () => this.focusEnd())
    // TP-12: an image pasted or dropped here uploads; its Markdown comes back to the caret,
    // unsent, like anything typed.
    onImages(this.input, files => this.upload("composer_image", files))
    this.handleEvent("image_uploaded", ({upload, markdown}) => {
      if (upload !== "composer_image") return
      if (this.imageAtEnd) appendLine(this.input, markdown)
      else insertAtCaret(this.input, markdown)
      this.imageAtEnd = false
      this.paint()
    })
    // !schedule: the text it took is in a scheduled message now.
    this.handleEvent("composer_scheduled", () => {
      this.input.value = this.sent
      this.input.setSelectionRange(this.sent.length, this.sent.length)
      this.paint()
    })
    this.paint()
  },

  destroyed() {
    document.removeEventListener("selectionchange", this.onSelection)
    document.removeEventListener("keydown", this.onPageKey)
    window.removeEventListener("idejo:appended", this.onAppended)
    window.removeEventListener("scroll", this.onScroll)
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

  command(name) {
    if (name === "image") {
      this.imageAtEnd = true
      document.querySelector("#composer-image-form input[type=file]")?.click()
    } else if (name === "new-topic") {
      if (this.unsent().trim() !== "") this.send(false, "new_topic")
      else this.pushEvent("new_topic", {})
    } else if (name === "poll" || name === "spoiler") {
      // The poll dialog gives the focus back to the box when it closes.
      if (name === "poll") InlineCard.opener = this.input
      if (this.unsent().trim() !== "") this.send(false, name)
      else this.pushEvent(name === "poll" ? "open_poll" : "spoiler", {})
    } else if (name === "schedule") {
      // The dialog gives the focus back to the box when it closes.
      InlineCard.opener = this.input
      this.pushEvent("open_schedule", {body: this.unsent().trim()})
    }
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
    if (body !== "" && this.sent === body + " ") return
    const old = this.sent
    const value = this.input.value
    const typed = old !== "" && value.startsWith(old) ? value.slice(old.length) : (old === "" ? value : "")
    const sent = body === "" ? "" : body + " "
    this.input.value = sent + typed
    this.sent = sent
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

  // `then`: what the server does once it is stored ("new_topic", "poll" or "spoiler").
  send(isBreak, then) {
    const caret = this.input.selectionStart
    const body = finishSentence(this.input.value, this.el.dataset.punctuate !== "false")
    // Editing a message (steward decision, 2026-10-24): emptied, the server asks whether to
    // delete it.
    if (body === "" && this.el.hasAttribute("data-editing")) {
      if (this.sent !== "") this.pushEvent("commit", {body: "", break: isBreak})
      return
    }
    if (body === "") return
    if (!isBreak && body === this.sent.replace(/\s+$/, "")) return

    const before = this.sent
    // Seen when sent (steward decision, 2026-10-25): it stays in sight, unless the author had
    // scrolled away from it.
    const shown = this.inView()
    const separator = isBreak ? "\n" : " "
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

    this.pushEvent("commit", then ? {body, break: isBreak, then} : {body, break: isBreak}, reply => {
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
  },

  paint() {
    const value = this.input.value
    const elapsed = this.burn ? performance.now() - this.burn.start : Infinity
    // A burn shows while it lasts and while the sent text is still the start of the box.
    const burning = elapsed < BURN_MS && this.burn.sent === this.sent && value.startsWith(this.sent)

    const painted = burning
      ? [...burnRuns(this.sent, this.burn.marks), ["composer-unsent", value.slice(this.sent.length)]]
      : sentRuns(this.sent, value).map(([text, sent]) => [sent ? "composer-sent" : "composer-unsent", text])
    const runs = withImages(painted, value, this.el.dataset.labelImage || "image:")

    const {selectionStart: start, selectionEnd: end} = this.input
    const caretAt = document.activeElement === this.input && start === end ? start : null

    // Nothing below may move while this repaints (steward report, 2026-10-25: the page shifted
    // up and down on phones as one typed and sent). The box keeps its height until it is
    // measured again, so the page never shrinks for a moment: scrolled to its end, the
    // browser would pull it up and leave it there. The scroll is put back in any case.
    const y = window.scrollY
    this.el.style.minHeight = `${this.el.offsetHeight}px`
    // The extra space keeps a trailing line break visible in the backdrop.
    this.backdrop.innerHTML = withCaret(runs, caretAt, caretAt == null ? "" : this.caret(value, caretAt)) + " "
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
    this.input.style.height = "auto"
    this.input.style.height = this.input.scrollHeight + "px"
    this.el.style.minHeight = ""
    if (window.scrollY !== y) window.scrollTo(window.scrollX, y)
  },

  // The part of the page the reader sees: the visual viewport, without an on-screen keyboard.
  visibleBand() {
    const vv = window.visualViewport
    return vv ? {top: vv.offsetTop, bottom: vv.offsetTop + vv.height} : {top: 0, bottom: window.innerHeight}
  },

  inView() {
    const r = this.input.getBoundingClientRect()
    const {top, bottom} = this.visibleBand()
    return r.bottom > top && r.top < bottom
  },

  // After a send the box can grow a line, or move down under the author's name (the first
  // Enter): scrolls just enough to keep its end above the keyboard.
  reveal() {
    const r = this.input.getBoundingClientRect()
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
