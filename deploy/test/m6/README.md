<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# M6 exit check

The milestone M6 check (MVP §7, "Ready for idejo Hub"), one command:

```sh
deploy/test/m6/run.sh               # everything, the mix flow test included
deploy/test/m6/run.sh --skip-flow   # without it (CI runs it in its Tests job)
```

It needs Docker with Compose v2, ports 80 and 443 free (for the default install's Caddy),
internet access (images, and Playwright from npm), and for the flow test Elixir and the
development database (`mix test`). It takes about ten minutes. It removes every container
and volume it made at the end, pass or fail, and exits non-zero on any failure (a failed
browser step leaves `failure.png` here). CI runs it nightly and on demand
(`.github/workflows/m6-exit-check.yml`).

## What it does

1. **Builds the image once** (`idejo-m6:check`, from the repository's `Dockerfile`) and starts,
   from `docker-compose.yml`:
   - one PostgreSQL server with two databases and two roles, `forum_a` and `forum_b`
     (`initdb/10-forums.sh`);
   - **two instances of that image**, `a.idejo.test` and `b.idejo.test`, each with its own
     database, secret key and volumes, run as behind any external proxy (AD-16): no Caddy of
     their own, `IDEJO_TRUSTED_PROXIES` naming the shared one;
   - **one Caddy** in front of all of them with its internal CA (`tls internal`); inside the
     check's network every name leads to it. The apps trust its root as one more authority
     (the system list mounted with it added); the image itself is unchanged;
   - **Dex** (`ghcr.io/dexidp/dex`, Apache-2.0) on `id.idejo.test`, the test OpenID Connect
     provider (`dex.yaml`): one member, a client for each forum.
2. **Sets both up with `bin/idejo-admin setup`** (AD-14), never the wizard: A open, B
   invite-only; an invite is made on B for the member.
3. **`GET /health` through Caddy** (AD-15) on both: `"status":"ok"`.
4. **One member, both forums** (AC-09), in a real browser (Playwright's Chromium, in its
   Docker image, `browser/check.mjs`): signs in to A with **Sign in with idejo ID**, and to B
   from B's invite link with **Sign up with idejo ID**, through Dex's login page. Then
   `run.sh` makes them moderator on A only, as A's owner (`Access.assign_role/3`), and the
   browser checks each forum's page of the member: Moderator on A, not on B.
5. **No session cookie crosses hosts** (SP-10): each forum's `_idejo_key` is host-only in
   the browser's cookie jar, and of every request the browser made (recorded with its
   `Cookie` header), none to one forum carried the other's session, nor any to Dex.
6. **Nothing single-server broke**: `mix test --only flow:admin-sets-up-the-server`, then the
   **default Compose install** (`deploy/docker-compose.yml`, unchanged, from the same image)
   comes up with app, database and the bundled Caddy, which answers on port 80.

Test values only: the provider's password and every secret are made up for the run.
