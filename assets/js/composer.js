// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Composer hook (M3): the text box is the author's open message (GM-02, GM-08, GM-10).
// Enter sends the whole text and keeps it in the box; sent text is drawn in
// higher contrast than unsent text by a backdrop behind a transparent textarea.

// The same rule as the server's (Idejo.Messages): a `.` is added after text that does not end
// with punctuation, but never after or inside code, where it would become part of the code.
const ENDS_WITH_PUNCTUATION = /[.!?…:;,)\]}"'»”’]$/u
const FENCE = /^\s*(```|~~~)/

export function finishSentence(text) {
  const body = text.replace(/\s+$/, "")
  if (body === "" || ENDS_WITH_PUNCTUATION.test(body)) return body
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

const escape = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

export const Composer = {
  mounted() {
    this.input = this.el.querySelector("textarea")
    this.backdrop = this.el.querySelector(".composer-backdrop")
    this.sent = ""
    // After a reload the author's open message is still theirs to continue (GM-12 grace).
    this.restore(this.el.dataset.sent || "")

    this.input.addEventListener("input", () => this.paint())
    this.input.addEventListener("keydown", e => {
      if (e.key !== "Enter" || e.isComposing || e.shiftKey) return
      e.preventDefault()
      // No Ctrl+Enter on touch screens for now (steward decision): their return is Enter.
      this.send(e.ctrlKey || e.metaKey)
    })
    // The server says what it holds of the open message, e.g. after a reconnect.
    this.handleEvent("composer_sent", ({body}) => this.restore(body))
    this.paint()
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

  send(isBreak) {
    const caret = this.input.selectionStart
    const body = finishSentence(this.input.value)
    if (body === "") return
    if (!isBreak && body === this.sent.replace(/\s+$/, "")) return

    const before = this.sent
    const separator = isBreak ? "\n" : " "
    // Keep the caret where it was unless it was at the end of the text (GM-02).
    const atEnd = caret >= this.input.value.replace(/\s+$/, "").length
    this.input.value = body + separator
    this.sent = this.input.value
    const position = atEnd ? this.input.value.length : caret
    this.input.setSelectionRange(position, position)
    this.paint()

    this.pushEvent("commit", {body, break: isBreak}, reply => {
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
