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
| AD | `lib/idejo/settings/`, `lib/idejo/setup/`, `lib/idejo/backup/`, `lib/idejo/release.ex` | Settings, first-run wizard, backup, CLI recovery |
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

The engine is `Idejo.Messages`: the composer sends the author's whole message after each Enter
and `commit/4` stores it (`break: true` for Ctrl+Enter), adding `.` after unpunctuated text
(not after code). Each commit overwrites `body_md`/`body_html`; one that changes text already
sent first keeps the old text in `message_versions` (GM-11). Events go to `"topic:{id}"` on
`Idejo.PubSub`: `{:message, message}` and `{:window_ended, id}`. The window length is the
`gm_window_seconds` setting (default 45). Tests set `recover_open_messages: false` and call
`Idejo.Messages.Recovery.run/0` themselves.

### Permissions

Roles (RP-01): the built-in roles owner, administrator, moderator, member and guest are created
by migration; a database trigger refuses to delete, rename or un-built-in them. Lower
`position` ranks higher. Guest and member are implicit, never stored in `user_roles`: visitors
and users with an unverified email act as guest (an unverified owner or administrator keeps
that role too); every verified user holds member on top of their other roles
(`Idejo.Access.roles_of/1`). Nobody is ever without a role.

Role editor (RP-02, **Admin → Roles**): custom roles have a name (unique ignoring case, also
against built-in names) and an optional `#rrggbb` colour, and can be renamed, moved one place
up or down, and deleted. Built-in roles only change colour. Owner and administrator stay on
top and guest stays last (`Access.movable?/1`). Every change is audited (`role.create`,
`role.update`, `role.reorder`, `role.delete`). Colours are drawn as SVG `fill`, never as
`style` (SP-05).

Role assignment (RP-06, **Admin → Users → a user**): `Access.assign_role/3` and
`Access.unassign_role/3`, audited as `role.grant` / `role.revoke`. Only owners give or remove
the owner role (steward decision, 2026-10-19); guest and member are never given. Removing
refuses the last owner and an administrator's own administrator role. When a user stops being
an administrator, their sessions' LiveViews are disconnected so open admin pages re-check.
The name colour is the colour of the highest-ranked role that has one (`Access.name_colour/1`).
`Access.grant_role/2` (unaudited) is only for setup and test fixtures.

Every read and write goes through `Idejo.Access.can?(user, right, category)`. Rights in v0.1:
`:view`, `:start`, `:post`, `:moderate`. Each role's right on a category is allow, deny or
unset; unset follows the role's server-wide setting (a `category_permissions` row with no
`category_id`), and deny overrides it (RP-04/RP-05). Across roles, **allow wins**: a right is
granted when any of the user's roles allows it, even if a higher-ranked role denies it (RP-06).
Search and lists filter by `:view` in the query, never after loading: use
`Idejo.Access.where_allowed(query, user, right)` for lists and `Access.can?/3` for one
category. Settings change only through `Access.set_permission/5` (audited as
`permission.update`). Server-wide defaults seeded at install: guest views; member views,
starts topics and posts; moderator also moderates.
The grid is **Admin → Permissions** (RP-05, `IdejoWeb.Admin.PermissionsLive`):
`/admin/permissions` for the server-wide settings (allow or not allowed, no deny) and
`/admin/permissions/{slug}` per category (server-wide, allow or deny); owner and administrator
rows show “Always” and take no setting.

**Owners and administrators always have every right and can never lock themselves out**
(steward rule, 2026-10-19). `Idejo.Access.administrator?/1` (holds owner or administrator) is
checked first by `can?/3` and the admin panel, and does not depend on email verification, other
roles or the permission grid. Every later change must keep it true:

- the permission grid has no deny for owner or administrator (RP-04/RP-05);
- role assignment cannot remove the last owner, and an administrator cannot remove their own
  administrator role (RP-06);
- the last owner cannot delete their account (AC-07) and owners and administrators cannot be
  banned (MO-02);
- the command line can always reset the owner's password (AD-09).

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
- **End-to-end flows** (MVP §4, §8): one test per flow in `test/idejo_web/flows/`, driving the
  real pages in order with ConnTest and LiveViewTest (no browser), tagged
  `@tag flow: "admin-sets-up-the-server"` etc.
- **No third-party scripts, fonts or analytics** (SP-04). Assets are served from the app.
- **No inline `<script>`, `<style>` or `style=""`** — the content security policy refuses them
  (SP-05, `IdejoWeb.Plugs.ContentSecurityPolicy`). Put code in `assets/js/` and styles in
  `assets/css/`; a dependency that needs inline code gets the per-request nonce from
  `conn.assigns.script_csp_nonce` / `style_csp_nonce`.
- **Public pages must work without JavaScript** (AX-04, CL-02). Use controllers, not LiveView.
- **All UI strings via Gettext** (`gettext/1`), never hard-coded (AX-05 readiness).
- **Content stored twice**: Markdown source and sanitised HTML (FD-03).
- **Every user, category, topic and message gets a stable `uri`** at creation (FD-01), and
  significant events write an `activities` row (FD-02). Use `Idejo.Federation`: primary keys
  are UUIDv7 from `generate_id/0`, the URI comes from `uri/2` (`<base_uri>/u/<id>`, `/c/`,
  `/t/`, `/m/`), and `activity_changeset/1` is inserted in the same transaction as the change.
- **Email verification gates taking part** (AC-01): unverified users can sign in, but only
  `Idejo.Accounts.confirmed?/1` users get posting rights (enforced through roles from RP-01).
- **Registration** (AC-02): `Accounts.register_user/2` enforces the `registration_mode` setting
  (open or invite-only) itself, so no sign-up path can skip it. Invites are single-use, valid
  7 days, made by administrators in **Admin → Invites**; the link is
  `/users/sign-up?invite=CODE`. Test fixtures create users with `skip_invite: true`.
- **Profile** (AC-04): `/users/settings` (`IdejoWeb.UserSettingsLive`, `live_session :signed_in`
  with the `{IdejoWeb.UserAuth, :require_authenticated}` hook) changes the display name
  through `Accounts.update_user_profile/2`, which records an `update` activity. The username
  never changes (@mentions); the avatar comes with uploads in M4. The same page changes the
  password (AC-01, below).
- **Deleting an account** (AC-07): `Accounts.delete_user/2`, from the profile with the
  password. The row stays (its `uri` and the records naming it keep working) but is
  anonymised: placeholder email and username that sign-up can never produce, "Deleted user",
  random password, roles, tokens and links deleted, `status: "deleted"`, and a `delete`
  activity. `Access.ensure_not_last_owner/1` refuses the last owner.
- **Passwords and sessions** (SP-02): Argon2id cost is pinned in `config/config.exs`. Session
  and remember-me cookies are encrypted, HttpOnly, SameSite=Lax and Secure (`:secure_cookies`,
  off only in dev). Sign-in renews the session; sign-out deletes the server-side token and
  disconnects the session's LiveViews via `live_socket_id`. Each sign-in gets a socket id,
  stored on its session tokens and kept when a token is reissued. A password reset (AC-02)
  deletes every token of the account and disconnects all its sessions
  (`UserAuth.disconnect_sessions/1`). A password change from the profile (AC-01,
  `Accounts.update_user_password/3`) needs the current password and does the same for every
  other session, keeping the one that made the change.
- **Categories** (RP-03, `Idejo.Forum`, **Admin → Categories**): one level (`parent_id` stays
  unused), ordered by `position`, at `/c/{slug}`. The slug is made from the name at creation
  (or chosen) and never changes, so renaming keeps links. Each change writes an audit entry
  (`category.create|update|reorder|delete`) and an activity in the same transaction.
  `visibility` is stored for RP-04, which turns it into view rights.
- **Topics** (TP-01, `Idejo.Forum`): `Forum.create_topic/3` needs the `:start` right and
  writes the topic and its first message, closed (GM-14), with URIs and `create` activities in
  one transaction. New topic: `/c/{slug}/new` (`NewTopicLive`, `live_session :member`). The
  topic page is a controller at `/t/{id}/{slug}`; `/t/{id}` (the URI) and stale slugs redirect
  there with 301.
- **Permalinks** (TP-06): a topic's URI `/t/{id}` 301s to `/t/{id}/{slug}`; a message's URI
  `/m/{id}` (`MessageController`) 302s to `/t/{id}/{slug}#message-{id}`, so both survive
  renames and moves. Each message's time links to its permalink. When topic pages are paged,
  `/m/{id}` must lead to the right page.
- **Posting and inline replies** (TP-08): `Forum.post_message/3` needs `Forum.can_post?/2`
  (the `:post` right and an open topic; locked and archived take nothing). It posts closed
  (until M3), moves `message_count` and `last_activity_at`, and records a `create` activity
  (`inReplyTo` for replies). A reply's `reply_to_id` must be a message of the same topic;
  replies stay in the one flow, shown with `Forum.excerpt/2` linking to `/m/{id}`. "Reply"
  links use `?reply_to={id}`, so choosing a message needs no JavaScript.
- **Live topics** (TP-04): the topic page stays a controller and embeds `IdejoWeb.TopicLive`
  (`live_render/3`, session `"topic_id"`, `"reply_to_id"`) for every viewer: the message list
  as a stream (`#message-{id}`, kept for permalinks) and the form for posters. Its first render
  is in the page's HTML (no JavaScript needed to read). Connected, it subscribes before
  loading; `{:message, m}` events update in place or append; a reconnect mounts again, which
  is the catch-up. Anything that changes a message must broadcast it after its transaction.
  Rights are checked at mount and again on `:permissions_changed`, which
  `Access.set_permission/5` broadcasts after a grid change (`Access.subscribe_permissions/0`;
  steward decision): a viewer who lost `:view` sees the list emptied and gets no more events.
- **Topic list** (TP-03): the category page lists `Forum.list_topics/2`, 30 a page (`?page=`),
  pinned first, then by `last_activity_at`, with starter, message count and last activity.
  The unread marker waits for read positions (TP-07, M4).
- **Message editor** (TP-02): `MessageComponents.editor/1`, a Markdown text box with Write /
  Preview, used for every message (the first message now, replies and the composer later).
  Nothing typed is stored or sent before posting; the preview is rendered for the author only.
- **Deleting a category with topics** (RP-03, TP-14): `Forum.delete_category/3` needs
  `topics: {:move, target}` or `topics: :archive` (else `{:error, :has_topics}`). Archived
  topics go, read-only (`state: "archived"`), to the one Archive category (`archive: true`),
  made on first use by `Forum.archive_category/1` with a `:view` deny for every role; admins
  show it to roles in the grid. The Archive is never deleted and takes no new topics
  (`Forum.can_start_topic?/2`).
- **Markdown** (FD-03): `Idejo.Markdown.to_html/1` (MDEx) renders with raw HTML off and
  sanitises the result; `body_html` is stored and shown as is (`MessageComponents.body/1`, the
  one raw output). No syntax highlighting: MDEx colours code with inline styles, which the CSP
  refuses.
- **Search engines** (SE-04): public pages set `canonical_url` (rendered as
  `<link rel="canonical">` by the root layout): `/`, `/c/{slug}` (`?page=n` from page 2) and
  `/t/{id}/{slug}` without `?reply_to=`. `/sitemap.xml` and `/robots.txt` come from
  `SitemapController` (no session); the sitemap lists only what a visitor may view
  (`Forum.list_public_topics/1`, at most 50,000 topics).
- **Guest reading** (AC-05): the home page and `/c/{slug}` are controllers
  (`PageController`, `CategoryController`) listing only what the visitor may view
  (`Forum.list_viewable_categories/1`, `Forum.get_viewable_category/2`). A category the visitor
  may not view answers 404, so its name is not given away.
- **Admin panel** (AD-02): LiveViews under `/admin` in `lib/idejo_web/live/admin/`, wrapped in
  `<Layouts.admin section={...}>`. The route needs `require_administrator` (plug) and the
  `live_session` hook `{IdejoWeb.UserAuth, :require_administrator}`; both use
  `Idejo.Access.administrator?/1` (owner or administrator, verified). Server-wide settings live
  in `Idejo.Settings`: declare each key with its default in `@definitions`.
- **Footer** (LI-02, LI-03): every page renders `Layouts.app`, whose footer carries the
  attribution notice word for word (never translated or reworded: AGPL section 7(b)) and the
  "Source code" link from `Idejo.Source.url/0` (upstream at the built commit, or
  `IDEJO_SOURCE_URL`). New pages must use `Layouts.app` so the footer is never missing.
- **First run** (AD-01): while no owner exists, `IdejoWeb.Plugs.RequireSetup` sends every page
  to `/setup`. The wizard needs the setup code written to the app log at boot
  (`Idejo.Setup.token/0`, in memory, new at each restart) and creates the owner, verified, in
  one locked transaction. Tests run with the redirect off (`setup_redirect: false`); a test
  that needs it turns it on and is not async.
- **Email** (AD-08): send with `Idejo.Mailer.deliver_email/1`, never `deliver/1`, so production
  uses the SMTP settings from **Admin → Email** (read at each send). Secret settings are
  declared with `secret: true` in `Idejo.Settings`: stored encrypted (`Settings.Secret`), never
  put in a form, audited as "[changed]". Tests can use `Idejo.SMTPCapture` for a real SMTP
  server.
- **Branding**: the header and page titles show the server name (`IdejoWeb.Layouts.server_name/0`),
  falling back to "Idejo". Pages set `page_title`; the title reads "Page · Server name". No
  framework branding in the interface.
- Emails built in a context use `IdejoWeb.Gettext` (the one Gettext backend); that is the only
  web module a context may reference.
- **Admin changes** to settings, roles, role assignments, categories or permissions write an
  `audit_log` row (SP-06): call `Idejo.Audit.record(admin, "subject.action", before, after)`
  in the same transaction as the change, with `Audit.snapshot/2` of the fields that matter and
  never a secret. The table is append-only (database trigger).
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
mix test --only flow:admin-sets-up-the-server   # one end-to-end flow (MVP §4)
mix test --only flow:member-starts-a-topic       # the M2 exit check
mix format --check-formatted
mix credo --strict
mix dialyzer
mix sobelow --config
mix deps.audit && mix hex.audit
reuse lint                         # SPDX headers (pip install reuse)
mix precommit                      # everything above that CI runs, Dialyzer too, but not reuse lint
```

Production bundle: `deploy/` (see `deploy/docker-compose.yml`). Server setup step by step:
`docs/deploying.md`.

## Milestones (MVP §7)

- [x] M0 — Foundations — repo, headers, NOTICE, CLA check, CI, Compose with HTTPS
- [x] M1 — Accounts and structure — roles, categories, permission grid, invites, profile, admin pages, audit log; exit test "admin sets up the server"
- [x] M2 — Topics
- [ ] **M3 — Growing messages**
- [ ] M4 — Around the conversation
- [ ] M5 — Moderation and operations

Current milestone: **M3**. Do not start work belonging to a later milestone.

M3 exit check (MVP §7): all GM tests pass; the "live conversation" flow passes as an
end-to-end test; a server restart mid-message loses nothing.

M2 exit check (MVP §7): the "member starts a topic" flow passes as an end-to-end test; a public
topic renders without JavaScript.
Not implemented in M2, left for later milestones:
- live delivery (TP-04), in M3;
- unread tracking (TP-07), along with TP-03's unread marker, in M4.

