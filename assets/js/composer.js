// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Composer hook: the text box is the author's open message (GM-02, GM-10).
// Enter sends the whole text and keeps it in the box; sent text is drawn in
// higher contrast than unsent text by a backdrop behind a transparent textarea.

// Text that already ends a sentence (closing quotes or brackets allowed).
const ENDS_WITH_PUNCTUATION = /[.!?…:;,]["'”’)\]»]*$/

export function finishSentence(text) {
  const body = text.replace(/\s+$/, "")
  if (body === "" || ENDS_WITH_PUNCTUATION.test(body)) return body
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

const escape = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

export const Composer = {
  mounted() {
    this.input = this.el.querySelector("textarea")
    this.backdrop = this.el.querySelector(".composer-backdrop")
    this.sent = ""

    this.input.addEventListener("input", () => this.paint())
    this.input.addEventListener("keydown", e => {
      if (e.key !== "Enter" || e.isComposing || e.shiftKey) return
      e.preventDefault()
      this.send(e.ctrlKey || e.metaKey)
    })
    this.paint()
  },

  // After a reconnect the server has a new session and no open message for it,
  // so everything in the box is unsent again (GM-12).
  reconnected() {
    this.sent = ""
    this.paint()
  },

  send(isBreak) {
    const caret = this.input.selectionStart
    const body = finishSentence(this.input.value)
    if (body === "") return
    if (!isBreak && body === this.sent.replace(/\s+$/, "")) return

    const separator = isBreak ? "\n" : " "
    // Keep the caret where it was unless it was at the end of the text.
    const atEnd = caret >= this.input.value.replace(/\s+$/, "").length
    this.input.value = body + separator
    this.sent = this.input.value
    const position = atEnd ? this.input.value.length : caret
    this.input.setSelectionRange(position, position)
    this.paint()

    this.pushEvent("commit", {body, break: isBreak}, reply => {
      if (!reply.closed) return
      // Ctrl+Enter after the window: the message closed, and anything typed
      // since starts the next one.
      const typed = this.input.value.startsWith(this.sent) ? this.input.value.slice(this.sent.length) : ""
      this.input.value = typed
      this.sent = ""
      this.input.setSelectionRange(typed.length, typed.length)
      this.paint()
    })
  },

  paint() {
    // The extra space keeps a trailing line break visible in the backdrop.
    this.backdrop.innerHTML = sentRuns(this.sent, this.input.value)
      .map(([text, sent]) => `<span class="${sent ? "composer-sent" : "composer-unsent"}">${escape(text)}</span>`)
      .join("") + " "
    this.input.style.height = "auto"
    this.input.style.height = this.input.scrollHeight + "px"
  },
}
