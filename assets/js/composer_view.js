// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The graphical composer's view (TP-11; steward decision, 2026-11-05): the message as it will
// look once sent, its Markdown out of sight as soon as it is written. Titles, bullets,
// numbered lists, quotes, small text, code, rules, links, bold, italic, strikethrough,
// highlight and spoilers (their text at 50% opacity), and images and GIFs drawn as pictures.
//
// The text box stays the composer: it holds the Markdown, the caret and the selection, and
// takes the keys (so sending, the timers, suggestions, undo and input methods work as in the
// plain composer). It is out of sight, and this view, drawn from its text at every change,
// is what the author sees, with its own caret and selection. `Layout` knows which characters
// are hidden (Markdown) and which are pictures, for the caret's moves and deletions; every
// piece of text drawn carries its place in the text (`data-s`), so a click or a tap finds it.

import {formatMarks, BOLD, ITALIC, STRIKE, SPOILER, MARKER, CODE, HIGHLIGHT} from "./composer_format"

const FENCE = /^ {0,3}(`{3,}|~{3,})/
// An uploaded image's Markdown, as the composer inserts it (IdejoWeb.ImageUploads).
const IMAGE = /!\[[^\]\n]*\]\((\/uploads\/[A-Za-z0-9-]+\.(?:jpe?g|png|gif|webp))\)/g
const LINK = /(?<!!)\[([^\]\n]+)\]\(([^)\s]+)\)/g

const FORMATS = [
  [BOLD, "md-b"], [ITALIC, "md-i"], [STRIKE, "md-s"], [SPOILER, "md-spoiler"], [CODE, "md-code"],
  [HIGHLIGHT, "md-hl"],
]

const escape = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")

// What starts a line: its kind, the Markdown hidden (`prefix` characters) and the drawing's
// data. A whole line is hidden for a fence or a rule.
function lineKind(line) {
  let m
  if ((m = line.match(/^ {0,3}(#{1,6})\s+/))) return {cls: `g-h g-h${m[1].length}`, prefix: m[0].length}
  if ((m = line.match(/^-#\s+/))) return {cls: "g-small", prefix: m[0].length}
  if (/^ {0,3}([-*_])( *\1){2,} *$/.test(line)) return {cls: "g-hr", prefix: line.length}
  if ((m = line.match(/^(\s*)([-*+])\s+/))) {
    return {cls: "g-ul", prefix: m[0].length, level: Math.min(4, Math.floor(m[1].length / 2))}
  }
  if ((m = line.match(/^(\s*)(\d{1,9})[.)]\s+/))) {
    return {cls: "g-ol", prefix: m[0].length, level: Math.min(4, Math.floor(m[1].length / 2)), n: m[2]}
  }
  if ((m = line.match(/^ {0,3}>\s?/))) return {cls: "g-quote", prefix: m[0].length}
  return {cls: "", prefix: 0}
}

export class Layout {
  // `gifs`: the GIF provider's Markdown pattern (composer.js's gifPattern), or null.
  constructor(value, gifs = null) {
    this.value = value
    const n = value.length
    this.marks = formatMarks(value)
    this.hidden = new Uint8Array(n)
    this.link = new Uint8Array(n)
    this.lines = []
    this.atoms = []
    const blockEnds = new Map()

    let fence = null, pos = 0
    for (const line of value.split("\n")) {
      const a = pos, b = pos + line.length
      const opening = line.match(FENCE)
      let kind
      if (fence) {
        if (opening && opening[1][0] === fence[0] && opening[1].length >= fence.length) {
          fence = null
          kind = {cls: "g-fence", prefix: line.length}
        } else {
          kind = {cls: "g-code", prefix: 0}
        }
      } else if (opening) {
        fence = opening[1]
        kind = {cls: "g-fence", prefix: line.length}
      } else {
        kind = lineKind(line)
      }
      for (let k = a; k < a + kind.prefix; k++) this.hidden[k] = 1
      if (kind.prefix > 0) blockEnds.set(a, a + kind.prefix)
      this.lines.push({a, b, ...kind})
      pos = b + 1
    }

    for (let k = 0; k < n; k++) if (this.marks[k] & MARKER) this.hidden[k] = 1

    for (const m of value.matchAll(LINK)) {
      const textFrom = m.index + 1, textTo = textFrom + m[1].length
      if (this.marks[m.index] & CODE) continue
      this.hidden[m.index] = 1
      for (let k = textTo; k < m.index + m[0].length; k++) this.hidden[k] = 1
      for (let k = textFrom; k < textTo; k++) this.link[k] = 1
    }

    const pictures = Array.from(value.matchAll(IMAGE), m => [m.index, m.index + m[0].length, m[1]])
    if (gifs) for (const m of value.matchAll(gifs)) pictures.push([m.index, m.index + m[0].length, m[1]])
    this.atoms = pictures.sort((x, y) => x[0] - y[0])
    for (const [a, b] of this.atoms) for (let k = a; k < b; k++) this.hidden[k] = 0

    // Runs of hidden characters (never across a line), the line's own Markdown first.
    this.intervals = []
    for (let k = 0; k < n;) {
      if (!this.hidden[k] || this.atomAt(k)) { k++; continue }
      let e = k
      while (e < n && this.hidden[e] && value[e] !== "\n" && !this.atomAt(e)) e++
      this.intervals.push({a: k, b: e, blockEnd: blockEnds.get(k) ?? null})
      k = e
    }
  }

  atomAt(k) {
    return this.atoms.find(([a, b]) => a <= k && k < b) || null
  }

  // The run of hidden characters touching position `p` (before, after or around it).
  around(p) {
    return this.intervals.find(({a, b}) => a <= p && p <= b) || null
  }

  endingAt(p) { return this.intervals.find(({b}) => b === p) || null }
  startingAt(p) { return this.intervals.find(({a}) => a === p) || null }

  next(p) {
    const code = this.value.charCodeAt(p)
    return p + (code >= 0xd800 && code <= 0xdbff ? 2 : 1)
  }

  prev(p) {
    const code = this.value.charCodeAt(p - 1)
    return p - (code >= 0xdc00 && code <= 0xdfff && p >= 2 ? 2 : 1)
  }

  // Where the caret at `p` is drawn and kept: never inside the Markdown nor inside a
  // picture's. Before Markdown that closes a format (after `bold` in `**bold**`), so typing
  // there goes on in it, as in a word processor; else after it.
  canonical(p) {
    const atom = this.atoms.find(([a, b]) => a < p && p < b)
    if (atom) return atom[1]
    const run = this.around(p)
    return run ? this.rest(run) : p
  }

  rest(run) {
    return this.closing(run) ? run.a : run.b
  }

  // Markdown right after formatted text (a closing `**`, `_`, `](url)`…).
  closing(run) {
    if (run.blockEnd !== null) return false
    const k = run.a - 1
    if (k < 0 || this.value[k] === "\n" || this.hidden[k] || this.atomAt(k)) return false
    return Boolean(this.marks[k] & (BOLD | ITALIC | STRIKE | SPOILER | CODE | HIGHLIGHT)) || Boolean(this.link[k])
  }

  // One visible step to the right or left of `p`: hidden Markdown is passed in the same step,
  // a picture is one step.
  stepRight(p) {
    const n = this.value.length
    if (p >= n) return n
    let q = this.next(p)
    for (;;) {
      const atom = this.atoms.find(([a, b]) => a < q && q < b)
      if (atom) return atom[1]
      const run = this.around(q)
      if (!run) return Math.min(q, n)
      if (run.a <= p && p <= run.b) {
        if (run.b >= n) return n
        p = run.b
        q = this.next(run.b)
        continue
      }
      return this.rest(run)
    }
  }

  stepLeft(p) {
    if (p <= 0) return 0
    let q = this.prev(p)
    for (;;) {
      const atom = this.atoms.find(([a, b]) => a < q && q < b)
      if (atom) return atom[0]
      const run = this.around(q)
      if (!run) return Math.max(q, 0)
      if (run.a <= p && p <= run.b) {
        if (run.a <= 0) return 0
        p = run.a
        q = this.prev(run.a)
        continue
      }
      return this.rest(run)
    }
  }

  // The word around `p` (a double click), as [from, to]; hidden Markdown ends a word.
  wordAt(p) {
    const value = this.value
    const word = k => k >= 0 && k < value.length && !this.hidden[k] && /[\p{L}\p{N}_'’-]/u.test(value[k])
    let a = p, b = p
    while (word(a - 1)) a--
    while (word(b)) b++
    return a === b ? [p, this.stepRight(p)] : [a, b]
  }

  // What Backspace at `p` takes away, as [from, to]: the character seen before the caret
  // (not the Markdown hidden there), a whole picture, or at the start of a list item, title
  // or quote its Markdown (it becomes a plain line). A format left empty goes with it.
  backspace(p) {
    if (p <= 0) return null
    const atom = this.atoms.find(([, b]) => b === p)
    if (atom) return [atom[0], atom[1]]
    const run = this.endingAt(p) || this.around(p)
    if (run && run.blockEnd !== null && p >= run.blockEnd) return [run.a, run.blockEnd]
    const y = run ? run.a : p
    if (y <= 0) return null
    const pictured = this.atoms.find(([, b]) => b === y)
    if (pictured) return [pictured[0], pictured[1]]
    return this.emptied(this.prev(y), y)
  }

  // What Delete at `p` takes away: the character seen after the caret, or a picture.
  forward(p) {
    const n = this.value.length
    const run = this.around(p)
    const x = run && run.b > p ? run.b : p
    if (x >= n) return null
    const atom = this.atoms.find(([a]) => a === x)
    if (atom) return [atom[0], atom[1]]
    return this.emptied(x, this.next(x))
  }

  // Deleting [x, y): when that empties a format (`**x**`, `[x](url)`), its Markdown goes too.
  emptied(x, y) {
    const before = this.endingAt(x)
    const after = this.startingAt(y)
    if (before && after && before.blockEnd === null) {
      const open = this.value.slice(before.a, before.b)
      const close = this.value.slice(after.a, after.b)
      if (open === [...close].reverse().join("") || (open.endsWith("[") && close.startsWith("]("))) {
        return [before.a, after.b]
      }
    }
    return [x, y]
  }
}

function formatClasses(mark) {
  return FORMATS.filter(([flag]) => mark & flag).map(([, cls]) => cls)
}

// The view's HTML. `options`:
//   base:    a class for each character (sent, unsent, burning), or null;
//   caret:   [position, HTML] to draw at the caret, or null;
//   select:  [start, end] of a selection, or null; `focus` its moving end (a `.g-focus`);
//   pending: [{at, url}] pictures still uploading, drawn where they will land;
//   placeholder: the box's placeholder, shown while it is empty.
export function render(layout, {base = null, caret = null, select = null, focus = null, pending = [], placeholder = ""} = {}) {
  const value = layout.value
  const events = new Map()
  const at = (p, html) => {
    const q = layout.canonical(p)
    events.set(q, (events.get(q) || "") + html)
  }
  if (caret) at(caret[0], caret[1])
  if (select && focus != null) at(focus, `<span class="g-focus"></span>`)
  for (const {at: p, url} of pending) {
    at(Math.min(p, value.length), `<span class="g-pending"><img src="${escape(url)}" alt=""></span>`)
  }

  if (value === "") {
    return `<div class="g-line" data-a="0" data-b="0">${events.get(0) || ""}` +
      `<span class="g-placeholder">${escape(placeholder)}</span></div>`
  }

  let html = ""
  for (const line of layout.lines) {
    const attrs = [`data-a="${line.a}"`, `data-b="${line.b}"`]
    if (line.level) attrs.push(`data-level="${line.level}"`)
    if (line.n) attrs.push(`data-n="${escape(line.n)}"`)
    html += `<div class="g-line ${line.cls}" ${attrs.join(" ")}>`

    let outer = null, piece = null, shown = false
    const flush = () => {
      if (!piece) return
      html += `<span data-s="${piece.s}"${piece.cls ? ` class="${piece.cls}"` : ""}>${escape(piece.text)}</span>`
      piece = null
    }
    const open = cls => {
      if (outer === cls) return
      flush()
      if (outer !== null) html += "</span>"
      html += `<span class="${cls || "g-run"}">`
      outer = cls
    }

    for (let p = line.a; p <= line.b; p++) {
      const event = events.get(p)
      if (event) { flush(); html += event }
      if (p === line.b) break

      const atom = layout.atoms.find(([a]) => a === p)
      if (atom) {
        open(base ? base[p] : "")
        flush()
        const selected = select && select[0] <= atom[0] && atom[1] <= select[1] ? " g-sel" : ""
        html += `<img class="g-image${selected}" src="${escape(atom[2])}" alt="" draggable="false" data-a="${atom[0]}" data-b="${atom[1]}">`
        shown = true
        p = atom[1] - 1
        continue
      }
      if (layout.hidden[p]) { flush(); continue }

      open(base ? base[p] : "")
      const classes = formatClasses(layout.marks[p])
      if (layout.link[p]) classes.push("g-link")
      if (select && select[0] <= p && p < select[1]) classes.push("g-sel")
      const cls = classes.join(" ")
      if (piece && piece.cls === cls && piece.s + piece.text.length === p) {
        piece.text += value[p]
      } else {
        flush()
        piece = {s: p, cls, text: value[p]}
      }
      shown = true
    }
    flush()
    if (outer !== null) html += "</span>"
    // An empty line (or one of Markdown only) keeps its height.
    if (!shown) html += "<br>"
    html += "</div>"
  }
  return html
}

// The place in the text of a point of the view (`node`, `offset`, as a selection or
// caretPositionFromPoint gives it), or null outside the drawn text.
export function sourceAt(view, node, offset) {
  if (!node || !view.contains(node)) return null
  if (node.nodeType === Node.TEXT_NODE) {
    const piece = node.parentElement.closest("[data-s]")
    if (piece && view.contains(piece)) return Number(piece.dataset.s) + Math.min(offset, node.length)
    node = node.parentElement
    offset = 0
  }
  if (node.dataset?.s !== undefined) return Number(node.dataset.s) + (offset > 0 ? node.textContent.length : 0)
  if (node.classList?.contains("g-image")) return Number(offset > 0 ? node.dataset.b : node.dataset.a)
  const children = Array.from(node.childNodes)
  // After the children: the end of the last that has a place, else the line's end.
  for (let k = offset; k < children.length; k++) {
    const p = edge(children[k], "start")
    if (p !== null) return p
  }
  for (let k = Math.min(offset, children.length) - 1; k >= 0; k--) {
    const p = edge(children[k], "end")
    if (p !== null) return p
  }
  const line = node.closest?.(".g-line")
  return line && view.contains(line) ? Number(line.dataset.b) : null
}

function edge(node, side) {
  if (node.nodeType !== Node.ELEMENT_NODE) return null
  if (node.classList.contains("g-line")) return Number(side === "start" ? node.dataset.a : node.dataset.b)
  if (node.classList.contains("g-image")) return Number(side === "start" ? node.dataset.a : node.dataset.b)
  if (node.dataset.s !== undefined) return Number(node.dataset.s) + (side === "end" ? node.textContent.length : 0)
  const pieces = node.querySelectorAll("[data-s], .g-image")
  if (pieces.length === 0) return null
  return edge(side === "start" ? pieces[0] : pieces[pieces.length - 1], side)
}

// The DOM point under (x, y), in the browser's way: [node, offset], or null.
export function pointAt(x, y) {
  if (document.caretPositionFromPoint) {
    const pos = document.caretPositionFromPoint(x, y)
    return pos ? [pos.offsetNode, pos.offset] : null
  }
  if (document.caretRangeFromPoint) {
    const range = document.caretRangeFromPoint(x, y)
    return range ? [range.startContainer, range.startOffset] : null
  }
  return null
}
