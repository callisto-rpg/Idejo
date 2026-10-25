// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The service worker (PN-17), served at /sw.js with the whole site as its scope by
// IdejoWeb.ServiceWorkerController, which embeds this file when it compiles. It is not
// bundled and imports nothing: everything it needs is here.
//
// Pushes come as Declarative Web Push JSON (PN-12): {"web_push": 8030, "notification":
// {"title", "body", "navigate", "tag", "lang"}, "app_badge": N}. Browsers that understand
// it show the notification themselves; for the others, this worker shows the same one.

self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()))

// Only links to this site are opened; anything else opens the home page.
const sameOrigin = href => {
  try {
    const url = new URL(href || "/", self.location.origin)
    return url.origin === self.location.origin ? url.href : self.location.origin + "/"
  } catch {
    return self.location.origin + "/"
  }
}

self.addEventListener("push", event => {
  let message
  try {
    message = event.data && event.data.json()
  } catch {
    return
  }
  const n = message && message.notification
  if (!n || typeof n.title !== "string") return

  const shown = self.registration.showNotification(n.title, {
    body: n.body || "",
    tag: n.tag,
    // A later push with the same tag replaces the notification and alerts again.
    renotify: Boolean(n.tag),
    lang: n.lang,
    icon: "/images/icon-192.png",
    data: {navigate: sameOrigin(n.navigate)}
  })

  const badge =
    typeof message.app_badge === "number" && self.navigator.setAppBadge
      ? message.app_badge > 0
        ? self.navigator.setAppBadge(message.app_badge)
        : self.navigator.clearAppBadge()
      : Promise.resolve()

  event.waitUntil(Promise.all([shown, badge.catch(() => {})]))
})

// Focus an open Idejo tab and take it to the notification's page, or open one.
self.addEventListener("notificationclick", event => {
  event.notification.close()
  const target = sameOrigin(event.notification.data && event.notification.data.navigate)

  event.waitUntil((async () => {
    const tabs = await self.clients.matchAll({type: "window", includeUncontrolled: true})
    const tab = tabs.find(client => new URL(client.url).origin === self.location.origin)
    if (!tab) return self.clients.openWindow(target)

    await tab.focus()
    try {
      // Only tabs this worker controls can be navigated from here.
      await tab.navigate(target)
    } catch {
      tab.postMessage({type: "idejo:navigate", href: target})
    }
  })())
})

// The push service replaced the subscription: subscribe again with the server's key and
// save the new one. The old endpoint proves which subscription it replaces (PN-17); without
// it (some browsers give none), the next page load saves the new one (PN-18).
self.addEventListener("pushsubscriptionchange", event => {
  event.waitUntil((async () => {
    const old = event.oldSubscription
    let key = old && old.options && old.options.applicationServerKey
    if (!key) {
      const response = await fetch("/push/key", {credentials: "omit"})
      if (!response.ok) return
      key = await response.text()
    }

    const renewed = event.newSubscription ||
      await self.registration.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: key})
    if (!old) return

    await fetch("/push/subscriptions/renew", {
      method: "POST",
      credentials: "omit",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({old_endpoint: old.endpoint, subscription: renewed.toJSON()})
    })
  })())
})
