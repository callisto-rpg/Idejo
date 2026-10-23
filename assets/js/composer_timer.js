// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The line under the composer (steward decision, 2026-10-23): it fills up until Ctrl+Enter
// may start a new message, from the message's first line to `data-end` (the window's end, or
// the unanswered message time's while nobody wrote below), then burns in and goes. The
// server's times come with its `data-now`, so the browser's clock does not matter. The fill
// is a CSS animation whose duration and (negative) delay are set through the DOM, never a
// style attribute (SP-05); a new end, when someone writes below, starts it again.

const SAME_END_MS = 1000

export const ComposerTimer = {
  mounted() {
    this.line = this.el.querySelector(".composer-timer-line")
    this.line.addEventListener("animationend", e => {
      if (e.animationName === "composer-timer-fill") this.burn()
      else if (e.animationName === "composer-timer-burn") this.el.hidden = true
    })
    this.run()
  },

  // Re-rendered every second while the window runs: only a new end restarts the line.
  updated() { this.run() },

  run() {
    const start = Number(this.el.dataset.start)
    const end = Number(this.el.dataset.end)
    const skew = Date.now() - Number(this.el.dataset.now)
    if (this.end !== undefined && Math.abs(this.end - end) < SAME_END_MS) return
    this.end = end

    const total = end - start
    const elapsed = Date.now() - skew - start
    this.el.hidden = false
    this.line.classList.remove("is-burning")
    // Over already (a reload after the time, or an answer that shortened it): nothing to show.
    if (total <= 0 || elapsed >= total) {
      if (this.started) this.burn()
      else this.el.hidden = true
      return
    }
    this.started = true
    this.line.style.animation = "none"
    void this.line.offsetWidth
    this.line.style.animation = ""
    this.line.style.animationDuration = `${total}ms`
    this.line.style.animationDelay = `-${Math.max(0, elapsed)}ms`
  },

  burn() {
    this.line.style.animationDelay = "0ms"
    this.line.style.animationDuration = ""
    this.line.classList.add("is-burning")
  },
}
