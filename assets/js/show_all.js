// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// ShowAll hook (GM-06): a message body taller than the screen is collapsed, with a
// "Show all" button that shows the rest. A growing message is measured again at each
// change, so it collapses once it gets that tall. Once shown in full it stays so.
// The state lives in data attributes the server never renders (JS.ignore_attributes).
//
// Text added at the end of a body (another user's append, or an edit adding to it; steward
// decision, 2026-10-25) burns in like the composer's sent text (.composer-burn), and the
// window hears of it (`idejo:appended`), so the composer can count appends above it. The
// markup says nothing of the open state (GM-07): the growth itself tells. The author's own
// open message is the composer, never a body here.

// Wraps the last `count` characters of `root`'s text in burning spans.
export function burnTail(root, count) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
  const nodes = []
  while (walker.nextNode()) nodes.push(walker.currentNode)
  for (let i = nodes.length - 1; i >= 0 && count > 0; i--) {
    const node = nodes[i]
    const target = count >= node.data.length ? node : node.splitText(node.data.length - count)
    count -= target.data.length
    if (target.data.trim() === "") continue
    const span = document.createElement("span")
    span.className = "composer-burn"
    target.replaceWith(span)
    span.appendChild(target)
  }
}

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
    this.seen = this.text.textContent
    this.update()
  },

  updated() {
    const now = this.text.textContent
    if (now.length > this.seen.length && now.startsWith(this.seen)) {
      burnTail(this.text, now.length - this.seen.length)
      window.dispatchEvent(new CustomEvent("idejo:appended", {detail: this.el}))
    }
    this.seen = now
    this.update()
  },

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
