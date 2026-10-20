// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// ShowAll hook (GM-06): a message body taller than the screen is collapsed, with a
// "Show all" button that shows the rest. A growing message is measured again at each
// change, so it collapses once it gets that tall. Once shown in full it stays so.
// The state lives in data attributes the server never renders (JS.ignore_attributes).
export const ShowAll = {
  mounted() {
    this.text = this.el.querySelector(".message-body")
    this.button = this.el.querySelector(".show-all")
    this.button.addEventListener("click", () => this.expand(true))
    // The button disappears once clicked, so focus moves to the text it showed. Tabbing to
    // a link in the hidden part shows it all, so focus never lands out of sight.
    this.text.addEventListener("focusin", () => this.expand(false))
    this.measure = () => this.update()
    window.addEventListener("resize", this.measure)
    this.observer = new MutationObserver(this.measure)
    this.observer.observe(this.text, {childList: true, subtree: true, characterData: true})
    this.update()
  },

  updated() { this.update() },

  destroyed() {
    window.removeEventListener("resize", this.measure)
    this.observer.disconnect()
  },

  expand(moveFocus) {
    if (!this.el.hasAttribute("data-collapsed")) return
    this.el.setAttribute("data-expanded", "")
    this.update()
    if (moveFocus) this.text.focus({preventScroll: true})
  },

  update() {
    const collapse = !this.el.hasAttribute("data-expanded") &&
      this.text.scrollHeight > window.innerHeight
    this.el.toggleAttribute("data-collapsed", collapse)
  },
}
