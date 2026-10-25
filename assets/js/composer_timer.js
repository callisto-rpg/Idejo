// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The line under the composer (steward decision, 2026-10-23): it fills up until Ctrl+Enter
// may start a new message, from the message's first line to `data-end` (the window's end, or
// the unanswered message time's while nobody wrote below), then burns in and goes. The
// server's times come with its `data-now`, so the browser's clock does not matter. The fill
// is a CSS animation whose duration and (negative) delay are set through the DOM, never a
// style attribute (SP-05); a new end, when someone writes below, starts it again.
//
// A bubble (steward decision, 2026-10-25) rides in front of the line saying "slow mode"; when
// the line is full it slides to the middle and says "Ctrl+Enter to start new message", and
// stays there while the line burns away. The line stops short by the bubble's width
// (`--bubble-room`), so the bubble never runs past the composer.
//
// At the bubble's right, while it says "slow mode", a monospace hint rides along (steward
// decision, 2026-10-25), its three lines (`data-labels`) taking turns every HINT_MS. Where it
// would run past the composer, it goes to the bubble's left, above the line (`is-left`), and
// with no room on either side (a phone), under the line (`is-under`).

const SAME_END_MS = 1000
const HINT_MS = 1500
const HINT_CHECK_MS = 250
// The space between the bubble and the hint (`--hint-gap` in app.css).
const HINT_GAP_PX = 8

// When, on this browser's clock, Ctrl+Enter may start a new message; null without a line
// (nothing open, or an edit).
let readyAt = null

// Whether Ctrl+Enter may start a new message now (the composer's Ctrl+Enter from anywhere).
export const mayStartNew = () => readyAt === null || Date.now() >= readyAt

export const ComposerTimer = {
  mounted() {
    this.line = this.el.querySelector(".composer-timer-line")
    this.bubble = this.el.querySelector(".composer-timer-bubble")
    this.slowLabel = this.bubble.textContent.trim()
    this.hint = this.el.querySelector(".composer-timer-hint")
    this.hints = JSON.parse(this.hint.dataset.labels || "[]")
    this.hintStart = Date.now()
    this.hintTimer = setInterval(() => this.showHint(), HINT_CHECK_MS)
    this.line.addEventListener("animationend", e => {
      if (e.animationName === "composer-timer-fill") this.burn()
    })
    // Tutorial bubbles turned on or off (theme.js): the line makes room for the bubble, or not.
    this.onBubbles = () => this.makeRoom()
    window.addEventListener("idejo:bubbles", this.onBubbles)
    this.run()
  },

  destroyed() {
    window.removeEventListener("idejo:bubbles", this.onBubbles)
    clearInterval(this.hintTimer)
    readyAt = null
  },

  makeRoom() {
    // The bubble's width with its "slow mode" label, or none while bubbles are off.
    if (this.bubble.classList.contains("is-done")) return
    this.el.style.setProperty("--bubble-room", `${this.bubble.offsetWidth}px`)
    this.showHint()
  },

  // The hint's line of the moment, at the bubble's right, or its left when there is no room.
  showHint() {
    if (this.bubble.classList.contains("is-done")) return
    const text = this.hints[Math.floor((Date.now() - this.hintStart) / HINT_MS) % this.hints.length] || ""
    if (this.hint.textContent !== text) this.hint.textContent = text
    // Measured in one line at the right, the way it rides when there is room.
    this.hint.classList.remove("is-left", "is-under")
    const width = this.hint.offsetWidth
    const bubble = this.bubble.getBoundingClientRect()
    const rail = this.el.getBoundingClientRect()
    if (bubble.right + HINT_GAP_PX + width <= rail.right + this.bubble.offsetWidth) return
    this.hint.classList.add(bubble.left - HINT_GAP_PX - width >= rail.left ? "is-left" : "is-under")
  },

  // Re-rendered every second while the window runs: only a new end restarts the line.
  updated() { this.run() },

  run() {
    const start = Number(this.el.dataset.start)
    const end = Number(this.el.dataset.end)
    const skew = Date.now() - Number(this.el.dataset.now)
    if (this.end !== undefined && Math.abs(this.end - end) < SAME_END_MS) return
    this.end = end
    readyAt = end + skew

    const total = end - start
    const elapsed = Date.now() - skew - start
    this.el.hidden = false
    this.line.classList.remove("is-burning", "is-over")
    this.bubble.classList.remove("is-done", "is-still")
    this.hint.hidden = false
    this.bubble.textContent = this.slowLabel
    this.makeRoom()
    // Over already (a reload after the time, or an answer that shortened it): only the bubble
    // in the middle, still.
    if (total <= 0 || elapsed >= total) {
      if (this.started) this.burn()
      else this.done(true)
      return
    }
    this.started = true
    for (const el of [this.line, this.bubble, this.hint]) {
      el.style.animation = "none"
      void el.offsetWidth
      el.style.animation = ""
      el.style.animationDuration = `${total}ms`
      el.style.animationDelay = `-${Math.max(0, elapsed)}ms`
    }
  },

  burn() {
    this.line.style.animationDelay = "0ms"
    this.line.style.animationDuration = ""
    this.line.classList.add("is-burning")
    this.done(false)
  },

  done(still) {
    this.bubble.style.animationDelay = "0ms"
    this.bubble.style.animationDuration = ""
    this.bubble.textContent = this.bubble.dataset.labelDone
    this.bubble.classList.add("is-done")
    this.hint.hidden = true
    if (still) {
      this.line.classList.add("is-over")
      this.bubble.classList.add("is-still")
    }
  },
}
