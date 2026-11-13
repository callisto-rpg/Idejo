// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Live formatting in the composer (TP-11; steward decision, 2026-11-05): while typing, bold,
// italic, strikethrough and ||spoilers|| show as they will once sent, their markers (`**`,
// `_`, `~~`, `||`) still visible, the text inside a spoiler at 50% opacity.
//
// The box is a transparent textarea over the backdrop that draws its text, so every
// character must keep its width: the styles in app.css (`.md-*` under `.composer-backdrop`)
// never change one (bold is an outline, italic each word skewed, strikethrough a line, a
// spoiler an opacity).
//
// `formatMarks/1` finds the spans as idejo's Markdown does (MDEx, CommonMark's delimiter
// rules, GitHub's strikethrough, Discord's spoilers, ==highlight==), per paragraph, leaving
// code (fenced blocks and `code spans`), escaped characters and bare links alone. It also
// marks `code spans` (CODE; their backticks, and escapes' backslashes, as markers) for the
// graphical composer (composer_view.js), which draws them; the plain composer does not.

export const BOLD = 1
export const ITALIC = 2
export const STRIKE = 4
export const SPOILER = 8
export const MARKER = 16
// Inline code and ==highlight== (the graphical composer draws them; the plain one leaves them).
export const CODE = 32
export const HIGHLIGHT = 64

const CLASSES = [
  [BOLD, "md-b"], [ITALIC, "md-i"], [STRIKE, "md-s"], [SPOILER, "md-spoiler"], [MARKER, "md-marker"],
  [CODE, "md-code"], [HIGHLIGHT, "md-hl"],
]

const FENCE = /^ {0,3}(`{3,}|~{3,})/
// A bare link's start (its `_` and `*` are not formatting).
const LINK = /^https?:[/][/]/
const space = ch => ch === undefined || /\s/u.test(ch)
const punct = ch => ch !== undefined && /[\p{P}\p{S}]/u.test(ch)

// One mark per character of `value` (UTF-16 units, as the textarea counts), a sum of the
// flags above.
export function formatMarks(value) {
  const marks = new Uint8Array(value.length)
  let fence = null, from = null, to = 0, pos = 0

  const flush = () => {
    if (from !== null) inline(value, from, to, marks)
    from = null
  }

  for (const line of value.split("\n")) {
    const opening = line.match(FENCE)
    if (fence) {
      if (opening && opening[1][0] === fence[0] && opening[1].length >= fence.length) fence = null
    } else if (opening) {
      flush()
      fence = opening[1]
    } else if (line.trim() === "") {
      flush()
    } else {
      if (from === null) from = pos
      to = pos + line.length
    }
    pos += line.length + 1
  }
  flush()
  return marks
}

// The delimiter runs of one paragraph, then CommonMark's matching of openers and closers.
function inline(value, from, to, marks) {
  const runs = []
  let i = from

  while (i < to) {
    const ch = value[i]

    if (ch === "\\" && punct(value[i + 1])) {
      // The backslash is only Markdown: a marker.
      marks[i] |= MARKER
      i += 2
    } else if (ch === "`") {
      const n = repeat(value, i, to, "`")
      const close = codeEnd(value, i + n, to, n)
      if (close === -1) {
        i += n
      } else {
        for (let k = i; k < close; k++) marks[k] |= CODE
        for (let k = i; k < i + n; k++) marks[k] |= MARKER
        for (let k = close - n; k < close; k++) marks[k] |= MARKER
        i = close
      }
    } else if (LINK.test(value.slice(i, i + 8))) {
      while (i < to && !space(value[i])) i++
    } else if (ch === "*" || ch === "_" || ch === "~" || ch === "|" || ch === "=") {
      const n = repeat(value, i, to, ch)
      if (((ch === "|" || ch === "=") && n === 2) || (ch === "~" && n <= 2) || ch === "*" || ch === "_") {
        runs.push(run(value, from, to, i, n, ch))
      }
      i += n
    } else {
      i++
    }
  }

  match(runs, marks)
}

const repeat = (value, i, to, ch) => {
  let j = i
  while (j < to && value[j] === ch) j++
  return j - i
}

// The end of a code span opened by `n` backticks, or -1 when none closes it.
function codeEnd(value, i, to, n) {
  while (i < to) {
    if (value[i] === "`") {
      const m = repeat(value, i, to, "`")
      if (m === n) return i + m
      i += m
    } else {
      i++
    }
  }
  return -1
}

// CommonMark's left- and right-flanking rules; `_` also may not open or close inside a word.
function run(value, from, to, start, n, ch) {
  const before = start > from ? value[start - 1] : undefined
  const after = start + n < to ? value[start + n] : undefined
  const left = !space(after) && (!punct(after) || space(before) || punct(before))
  const right = !space(before) && (!punct(before) || space(after) || punct(after))
  const open = ch === "_" ? left && (!right || punct(before)) : left
  const close = ch === "_" ? right && (!left || punct(after)) : right
  // An opener is used up from its inner end, a closer from its start.
  return {ch, start, n, size: n, closeAt: start, open, close, active: true}
}

function compatible(opener, closer) {
  if (opener.ch !== closer.ch) return false
  // Strikethrough and spoilers close only with a run as long as their opener.
  if (opener.ch === "~" || opener.ch === "|" || opener.ch === "=") return opener.n === closer.n
  // The rule of three.
  if ((opener.close || closer.open) && (opener.size + closer.size) % 3 === 0) {
    return opener.size % 3 === 0 && closer.size % 3 === 0
  }
  return true
}

function match(runs, marks) {
  runs.forEach((closer, c) => {
    if (!closer.close) return

    while (closer.n > 0) {
      let o = c - 1
      while (o >= 0 && !(runs[o].active && runs[o].open && runs[o].n > 0 && compatible(runs[o], closer))) o--
      if (o < 0) return

      const opener = runs[o]
      const use = opener.ch === "*" || opener.ch === "_" ? (opener.n >= 2 && closer.n >= 2 ? 2 : 1) : opener.n
      const flag = {"~": STRIKE, "|": SPOILER, "=": HIGHLIGHT}[opener.ch] || (use === 2 ? BOLD : ITALIC)
      const innerFrom = opener.start + opener.n
      const innerTo = closer.closeAt

      for (let k = innerFrom - use; k < innerFrom; k++) marks[k] |= MARKER
      for (let k = innerTo; k < innerTo + use; k++) marks[k] |= MARKER
      for (let k = innerFrom; k < innerTo; k++) marks[k] |= flag

      opener.n -= use
      closer.n -= use
      closer.closeAt += use
      // Runs between them can no longer pair across this span.
      for (let k = o + 1; k < c; k++) runs[k].active = false
      if (opener.n === 0) opener.active = false
    }
  })
}

const classes = mark => CLASSES.filter(([flag]) => mark & flag).map(([, cls]) => cls).join(" ")

const escape = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

// Italic is each word slanted on its own (`.md-w`, an inline block, skewed): a transform
// never moves anything, and the spaces between stay where lines may wrap.
const slanted = text =>
  text.split(/(\s+)/).map(part => part === "" || /^\s+$/.test(part) ? escape(part) : `<span class="md-w">${escape(part)}</span>`).join("")

// `text`, which starts at character `start` of the box, as HTML: each piece with its own
// formatting in a span of `.md-*` classes, nested inside the run's span, so the run (sent
// text, or the unsent highlight) stays one box.
export function formatted(text, start, marks) {
  let html = "", from = 0
  while (from < text.length) {
    const mark = (marks && marks[start + from]) || 0
    let to = from + 1
    while (to < text.length && ((marks && marks[start + to]) || 0) === mark) to++
    const piece = mark & ITALIC ? slanted(text.slice(from, to)) : escape(text.slice(from, to))
    html += mark ? `<span class="${classes(mark)}">${piece}</span>` : piece
    from = to
  }
  return html
}
