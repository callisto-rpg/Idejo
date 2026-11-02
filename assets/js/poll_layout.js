// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// PollLayout hook (steward decision, 2026-11-02): a poll's answers stand side by side, each a
// column 5.5rem wide; on a narrow screen the columns shrink (CSS) so the bars and emojis stay
// on one line. When they had to shrink and an answer's text no longer fits its column (a word
// wider than it, or more than three lines), the poll takes data-layout="list": the bars,
// counts and emojis stay columns, and each answer becomes a row under them (app.css). With
// room, nothing changes. Measured again when the poll's width changes or the server redraws
// it; data-layout is kept across patches (JS.ignore_attributes, PollComponents.poll/1).

const COLUMN_REM = 5.5
const MAX_LINES = 3

export const PollLayout = {
  mounted() {
    this.width = null
    this.observer = new ResizeObserver(() => {
      // Only the width decides; the layout changes the height, which must not loop.
      if (this.el.clientWidth !== this.width) this.layout()
    })
    this.observer.observe(this.el)
    this.layout()
  },

  updated() { this.layout() },

  destroyed() { this.observer.disconnect() },

  layout() {
    const el = this.el
    this.width = el.clientWidth
    // Measured as columns, with words kept whole.
    delete el.dataset.layout
    el.dataset.measuring = ""
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16
    const options = Array.from(el.querySelectorAll(".poll-option"))
    const shrunk = options.some(option => option.getBoundingClientRect().width < COLUMN_REM * rem - 1)
    const tooLong = shrunk && Array.from(el.querySelectorAll(".poll-answer-text")).some(text => {
      const lineHeight = parseFloat(getComputedStyle(text).lineHeight) || rem * 1.25
      return text.scrollWidth > text.clientWidth + 1 || text.offsetHeight > lineHeight * MAX_LINES + 1
    })
    delete el.dataset.measuring
    if (tooLong) el.dataset.layout = "list"
  },
}
