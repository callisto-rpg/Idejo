// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The notifications banner (PN-20 to PN-23), rendered hidden by the server on category and
// topic pages when `Push.banner?/1` allows it. Shown here only:
//   * where push is supported and the browser's permission is still undecided: "Turn on"
//     (the only thing that asks for permission) and "Not now";
//   * in an iPhone or iPad Safari tab, which takes notifications only from the Home Screen:
//     how to add the site there, without "Turn on" (PN-22).
// Granted: it says "Notifications are on" and goes; denied: it goes (and the browser never
// lets it show again). "Not now" records the dismissal on the server and hides it. It never
// takes the focus; one that was on its buttons goes to the page's main content.
import {appleTouch, enablePush, fromHomeScreen, pushSupported} from "./push"

const ON_MS = 4000

const csrfToken = () => document.querySelector("meta[name='csrf-token']")?.content

const hide = banner => {
  const hadFocus = banner.contains(document.activeElement)
  banner.hidden = true
  if (hadFocus) document.getElementById("main")?.focus()
}

const part = (banner, name) => banner.querySelector(`.push-banner-${name}`)

function setUp() {
  const banner = document.getElementById("push-banner")
  if (!banner || banner.dataset.ready) return
  banner.dataset.ready = "true"
  // No key: push is off, or nobody is signed in.
  if (!document.querySelector("meta[name='push-key']")) return

  if (appleTouch() && !fromHomeScreen()) {
    part(banner, "offer").hidden = true
    part(banner, "ios").hidden = false
    part(banner, "turn-on").hidden = true
  } else if (!pushSupported() || Notification.permission !== "default") {
    return
  }
  banner.hidden = false

  part(banner, "turn-on").addEventListener("click", async () => {
    let permission
    try {
      permission = await enablePush()
    } catch (error) {
      console.warn("Idejo push:", error)
      return hide(banner)
    }
    if (permission !== "granted") return hide(banner)
    part(banner, "offer").hidden = true
    part(banner, "on").hidden = false
    part(banner, "actions").hidden = true
    setTimeout(() => hide(banner), ON_MS)
  })

  part(banner, "not-now").addEventListener("click", () => {
    hide(banner)
    fetch("/push/banner/dismiss", {method: "POST", headers: {"x-csrf-token": csrfToken()}})
      .catch(() => {})
  })
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", setUp)
else setUp()
