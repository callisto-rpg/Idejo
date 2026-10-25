// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// PushSettings hook (PN-24), on the profile's "Push notifications" section: this browser's
// state, one line of the markup shown:
//   * on: allowed and subscribed;
//   * off: allowed but not subscribed, or not asked yet, with "Turn on";
//   * blocked: denied, with how to allow it again;
//   * ios: an iPhone or iPad Safari tab, with the Home Screen steps (PN-22);
//   * unsupported: no push in this browser.
// It tells the view which device is this browser ("push_endpoint"), that the devices changed
// after "Turn on" ("push_changed"), and ends this browser's subscription when the view says
// it was removed ("push_unsubscribe").
import {appleTouch, currentEndpoint, disablePush, enablePush, fromHomeScreen, pushSupported} from "./push"

const STATES = ["unknown", "on", "off", "blocked", "ios", "unsupported"]

export const PushSettings = {
  mounted() {
    this.el.querySelector(".push-browser-turn-on")?.addEventListener("click", () => this.turnOn())
    this.handleEvent("push_unsubscribe", async () => {
      await disablePush().catch(error => console.warn("Idejo push:", error))
      this.refresh()
    })
    this.refresh()
  },

  show(state) {
    for (const name of STATES) {
      const part = this.el.querySelector(`.push-browser-${name}`)
      if (part) part.hidden = name !== state
    }
  },

  async refresh() {
    if (appleTouch() && !fromHomeScreen()) return this.show("ios")
    if (!pushSupported()) return this.show("unsupported")
    if (Notification.permission === "denied") return this.show("blocked")

    let endpoint = null
    try {
      endpoint = await currentEndpoint()
    } catch (error) {
      console.warn("Idejo push:", error)
    }
    this.pushEvent("push_endpoint", {endpoint})
    this.show(endpoint ? "on" : "off")
  },

  async turnOn() {
    try {
      await enablePush()
    } catch (error) {
      console.warn("Idejo push:", error)
    }
    this.pushEvent("push_changed", {})
    this.refresh()
  },
}
