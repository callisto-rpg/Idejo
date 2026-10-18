<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# CLAUDE.md — Idejo

Read this file before every task. Update it in the same pull request whenever a change
affects architecture, conventions, commands or milestone status (DV-01).

## What Idejo is

A self-hosted community server: one install hosts one community, organised like a forum
(categories → topics → messages), where every topic is a live chat. Quick lines sent with
Enter merge into one **growing message**. The composer is the open message: sent text stays in
it, and a fixed window (45 s default) only sets how soon the author may start a new message
with Ctrl+Enter, so conversations read like a forum while feeling like a chat.

## Specifications — the source of truth

- `Idejo — MVP Spec Sheet v0.1.md` — **what we are building now.** Scope, cut-down
  requirements, flows, screens, data model, milestones, definition of done.
- `Community Platform — Spec Sheet v1.md` — full v1 requirements. Anything the MVP sheet
  does not mention follows v1.

Requirement IDs (e.g. `GM-03`) are stable. Never renumber them. If a task is not covered by
an ID, stop and ask; do not invent behaviour. The specs are written by the steward, not by
Claude; do not edit them unless asked (LI-08).

## Stack

Elixir + Phoenix (LiveView for the signed-in app, plain controllers for public pages),
PostgreSQL (data, full-text search, Oban jobs), Caddy (TLS), shipped as Docker Compose.
Versions are pinned in `.tool-versions` and `mix.lock` (DV-04).

## Architecture

```
lib/idejo/            business logic (contexts) — no web code, no Phoenix imports
lib/idejo_web/        web layer — controllers (public, no-JS), live/ (signed-in), components/, plugs/
```

| Prefix | Context folder | Notes |
| --- | --- | --- |
| GM | `lib/idejo/messages/` | Growing-message engine (see below) |
| TP | `lib/idejo/forum/`, `lib/idejo/reading/` | Topics, fork, move, lock, pin; read positions, follows |
| RP | `lib/idejo/access/` | Roles, category permissions, `Idejo.Access.can?/3` |
| AC | `lib/idejo/accounts/` | Users, sessions, invites, password reset |
| MO | `lib/idejo/moderation/` | Reports, mod actions, bans |
| SE | `lib/idejo/search/` | Postgres full-text, permission-aware |
| NO | `lib/idejo/notifications/` | In-app only in v0.1 |
| FD | `lib/idejo/federation/` | URIs, activities outbox |
| AD | `lib/idejo/settings/`, `lib/idejo/backup/`, `lib/idejo/release.ex` | Settings, backup, CLI recovery |
| SP | `lib/idejo/audit/`, `lib/idejo_web/plugs/` | Audit log, CSP, rate limits |
| AX, CL, SE-04 | `lib/idejo_web/` | Accessibility, public rendering |

### Growing-message invariants (GM, NF-02) — never break these

1. A commit is written to the database **before** the append is acknowledged.
2. `closes_at = opened_at + window` is fixed at the first commit. Appends never change it.
   It marks when the author may start a new message; it never closes the message (GM-03/04).
3. One `Idejo.Messages.OpenMessage` process per open message holds the window timer, under
   `OpenMessageSupervisor`. The database is the truth; the process is only a timer.
4. On boot, `Idejo.Messages.Recovery` reloads open messages with their original `closes_at`.
5. A message closes only on Ctrl+Enter after the window (GM-05), lock or archive, session
   disconnect (GM-12) or a moderator (GM-16).
6. At most one open message per author per topic (GM-09). The first message of a topic is
   never open (GM-14).
7. Notifications, unread counts and search treat a growing message as one item (GM-13).

### Permissions

Every read and write goes through `Idejo.Access.can?(user, right, category)`. Rights in v0.1:
`:view`, `:start`, `:post`, `:moderate`. An explicit deny wins (RP-06). Search and lists filter
by `:view` in the query, never after loading.

## Conventions

- **SPDX header** on every source file (LI-01):
  ```elixir
  # SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
  # SPDX-License-Identifier: AGPL-3.0-only
  ```
  Files that cannot hold comments are covered in `REUSE.toml`.
- **Tests per requirement** (DV-02): name the test after the ID and tag it.
  ```elixir
  @tag req: "GM-03"
  test "GM-03 appends never extend the window" do
  ```
- **No third-party scripts, fonts or analytics** (SP-04). Assets are served from the app.
- **No inline `<script>`, `<style>` or `style=""`** — the content security policy refuses them
  (SP-05, `IdejoWeb.Plugs.ContentSecurityPolicy`). Put code in `assets/js/` and styles in
  `assets/css/`; a dependency that needs inline code gets the per-request nonce from
  `conn.assigns.script_csp_nonce` / `style_csp_nonce`.
- **Public pages must work without JavaScript** (AX-04, CL-02). Use controllers, not LiveView.
- **All UI strings via Gettext** (`gettext/1`), never hard-coded (AX-05 readiness).
- **Content stored twice**: Markdown source and sanitised HTML (FD-03).
- **Every user, category, topic and message gets a stable `uri`** at creation (FD-01), and
  significant events write an `activities` row (FD-02).
- **Admin changes** to settings, roles or permissions write an `audit_log` row (SP-06).
- Contexts expose plain functions returning `{:ok, _} | {:error, _}`; LiveViews stay thin.
- No new dependency without a licence check: MIT, BSD, Apache-2.0 or similar only (LI-06).

## Workflow

- One requirement or fix per pull request (DV-05). Mention the ID in the PR title.
- Commits made with Claude Code end with the trailer `Assisted-by: Claude Code` (LI-08).
- A person reviews every PR. Changes to `accounts/`, `access/`, `uploads/` and `plugs/` get
  an extra careful human review (DV-06) — flag them in the PR description.

## Commands

```sh
mise install                       # or: asdf install — Erlang + Elixir from .tool-versions
docker compose up -d               # dev PostgreSQL on localhost:5432
mix setup                          # deps, database, assets
mix phx.server                     # http://localhost:4000
mix test                           # all tests
mix test --only req:GM-03          # tests for one requirement
mix format --check-formatted
mix credo --strict
mix dialyzer
mix sobelow --config
mix deps.audit && mix hex.audit
reuse lint                         # SPDX headers (pip install reuse)
mix precommit                      # everything above that CI runs (alias in mix.exs)
```

Production bundle: `deploy/` (see `deploy/docker-compose.yml`). Server setup step by step:
`docs/deploying.md`.

## Milestones (MVP §7)

- [x] M0 — Foundations — repo, headers, NOTICE, CLA check, CI, Compose with HTTPS
- [ ] **M1 — Accounts and structure**
- [ ] M2 — Topics
- [ ] M3 — Growing messages
- [ ] M4 — Around the conversation
- [ ] M5 — Moderation and operations

Current milestone: **M1**. Do not start work belonging to a later milestone.
