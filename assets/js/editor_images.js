// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// EditorImages hook (TP-12): an image pasted or dropped into the message editor uploads
// under the editor's upload name (data-upload), and its Markdown is inserted at the caret.
// The input event lets the form's phx-change see the new text.
import {onImages, insertAtCaret} from "./composer"

export const EditorImages = {
  mounted() {
    const name = this.el.dataset.upload
    const input = () => this.el.querySelector("textarea")
    onImages(this.el, files => this.upload(name, files))
    this.handleEvent("image_uploaded", ({upload, markdown}) => {
      if (upload !== name || !input()) return
      insertAtCaret(input(), markdown)
      input().dispatchEvent(new Event("input", {bubbles: true}))
    })
  },
}
