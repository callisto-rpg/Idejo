// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Web push in the page (PN-18). The root layout gives signed-in users a
// <meta name="push-key"> with the server's VAPID public key while push is on (PN-19); with
// none, this does nothing.
//
// On every page load where notifications are allowed, the browser's subscription is taken
// (made again if it is missing, or was made with an older key) and saved to the server, so
// subscriptions a browser renews silently are never lost. Declarative push (window.pushManager)
// is used where the browser has it, else the service worker's.
// `enablePush()` asks for permission and subscribes: the banner (PN-21) and the settings
// page (PN-24) call it, and only from a click.

const pushKey = () => document.querySelector("meta[name='push-key']")?.content
const csrfToken = () => document.querySelector("meta[name='csrf-token']")?.content

export const pushSupported = () =>
  "serviceWorker" in navigator && "Notification" in window &&
  ("pushManager" in window || "PushManager" in window)

const keyBytes = key => {
  const base64 = key.replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(base64 + "=".repeat((4 - base64.length % 4) % 4))
  return Uint8Array.from(raw, c => c.charCodeAt(0))
}

const sameKey = (subscription, key) => {
  const current = subscription.options?.applicationServerKey
  if (!current) return true
  const a = new Uint8Array(current), b = keyBytes(key)
  return a.length === b.length && a.every((byte, i) => byte === b[i])
}

const registration = () => navigator.serviceWorker.register("/sw.js", {scope: "/"})

const manager = async () => window.pushManager || (await registration()).pushManager

const save = subscription =>
  fetch("/push/subscriptions", {
    method: "POST",
    headers: {"content-type": "application/json", "x-csrf-token": csrfToken()},
    body: JSON.stringify(subscription.toJSON())
  })

// The current subscription, made again when missing or made with an older key (PN-14).
const subscription = async key => {
  const pushManager = await manager()
  let current = await pushManager.getSubscription()
  if (current && !sameKey(current, key)) {
    await current.unsubscribe()
    current = null
  }
  return current || pushManager.subscribe({userVisibleOnly: true, applicationServerKey: keyBytes(key)})
}

export async function syncPush() {
  const key = pushKey()
  if (!key || !pushSupported() || Notification.permission !== "granted") return
  // The service worker shows pushes where declarative push is missing, and opens their links.
  await registration()
  await save(await subscription(key))
}

// Asks for permission (only from a click: PN-21) and subscribes. Resolves to the permission.
export async function enablePush() {
  const key = pushKey()
  if (!key || !pushSupported()) return "unsupported"
  const permission = await Notification.requestPermission()
  if (permission === "granted") {
    await registration()
    const response = await save(await subscription(key))
    if (!response.ok) throw new Error(`push subscription refused: ${response.status}`)
  }
  return permission
}

// The service worker asks an open tab it does not control to go to a notification's page.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.addEventListener("message", event => {
    const {type, href} = event.data || {}
    if (type === "idejo:navigate" && new URL(href, location.href).origin === location.origin) {
      location.assign(href)
    }
  })
}

syncPush().catch(error => console.warn("Idejo push:", error))
