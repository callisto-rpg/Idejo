// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// M6 exit check, in a real browser (Playwright's Chromium, Apache-2.0), run by run.sh inside
// the check's network, where a.idejo.test, b.idejo.test and id.idejo.test lead to Caddy.
//
// 1. One member signs in to both forums through the test provider (Dex): A is open, B is
//    invite-only, so on B they use the invite run.sh made (B_INVITE), from its sign-up page.
// 2. Each forum's session cookie is host-only, and the browser never sends one forum's
//    session to the other (every request it makes is recorded with its Cookie header).
// 3. Once run.sh has made them moderator on A only (it waits for /out/signed-in, then
//    writes /out/ids), each forum shows only its own roles.

import { chromium } from "playwright"
import { existsSync, readFileSync, writeFileSync } from "node:fs"

const PASSWORD = "m6 exit check member"
const EMAIL = "member@idejo.test"
const OUT = "/out"

function check(ok, message) {
  if (!ok) throw new Error(message)
  console.log(`  ok  ${message}`)
}

const browser = await chromium.launch()
// Caddy's internal CA is not the browser's; the apps trust it, the browser need not.
const context = await browser.newContext({ ignoreHTTPSErrors: true })
const page = await context.newPage()

const sent = []
page.on("request", async request => {
  const url = new URL(request.url())
  const headers = await request.allHeaders()
  sent.push({ host: url.hostname, cookie: headers.cookie || "" })
})

async function signIn(host, invite) {
  if (invite) {
    await page.goto(`https://${host}/users/sign-up?invite=${encodeURIComponent(invite)}`)
    await page.click("#oidc-sign-up")
  } else {
    await page.goto(`https://${host}/users/sign-in`)
    await page.click("#oidc-sign-in")
  }
  await page.waitForURL(url => ["id.idejo.test", host].includes(new URL(url).hostname))

  // Dex keeps no session of its own here: it asks every time.
  if (new URL(page.url()).hostname === "id.idejo.test") {
    await page.fill("#login", EMAIL)
    await page.fill("#password", PASSWORD)
    await page.click("#submit-login")
  }

  await page.waitForURL(`https://${host}/`)
  await page.goto(`https://${host}/users/settings`)
  check(new URL(page.url()).pathname === "/users/settings", `${host}: signed in through Idejo ID`)
}

async function roles(host, id) {
  await page.goto(`https://${host}/u/${id}`)
  return page.locator('ul[aria-label="Roles"] li').allInnerTexts()
}

try {
  await signIn("a.idejo.test")
  await signIn("b.idejo.test", process.env.B_INVITE)

  // SP-10: host-only session cookies, one per forum.
  const sessions = (await context.cookies()).filter(cookie => cookie.name === "_idejo_key")
  const domains = sessions.map(cookie => cookie.domain).sort()
  check(
    JSON.stringify(domains) === JSON.stringify(["a.idejo.test", "b.idejo.test"]),
    `one session cookie per forum, host-only (${domains.join(", ")})`
  )

  for (const cookie of await context.cookies()) {
    check(!cookie.domain.startsWith("."), `${cookie.name} on ${cookie.domain} has no Domain`)
  }

  writeFileSync(`${OUT}/signed-in`, "")
  console.log("  ..  waiting for the roles (run.sh)")

  for (let i = 0; i < 600 && !existsSync(`${OUT}/ids`); i++) await page.waitForTimeout(500)
  check(existsSync(`${OUT}/ids`), "run.sh gave the member a role on A")
  const ids = JSON.parse(readFileSync(`${OUT}/ids`, "utf8"))

  const rolesA = await roles("a.idejo.test", ids.a)
  const rolesB = await roles("b.idejo.test", ids.b)
  check(rolesA.includes("Moderator"), `A shows the member as Moderator (${rolesA.join(", ")})`)
  check(!rolesB.includes("Moderator"), `B does not (${rolesB.join(", ")})`)
  check(rolesA.includes("Member") && rolesB.includes("Member"), "both show Member")

  // Every request so far, to either forum: never the other forum's session.
  const value = host => sessions.find(cookie => cookie.domain === host).value
  const leaks = sent.filter(
    ({ host, cookie }) =>
      (host === "b.idejo.test" && cookie.includes(value("a.idejo.test"))) ||
      (host === "a.idejo.test" && cookie.includes(value("b.idejo.test"))) ||
      (host === "id.idejo.test" && cookie.includes("_idejo_key"))
  )

  check(sent.some(({ host }) => host === "b.idejo.test"), "requests to B were recorded")
  check(leaks.length === 0, `no request carried another host's session (${sent.length} requests)`)
} catch (error) {
  console.error(`FAILED: ${error.message}`)
  await page.screenshot({ path: `${OUT}/failure.png` }).catch(() => {})
  process.exitCode = 1
} finally {
  await browser.close()
}
