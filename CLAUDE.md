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
it, and a fixed window (15 s default) only sets how soon the author may start a new message
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
5. A message closes only on Ctrl+Enter after the window (GM-05; with nothing below it, also
   after the unanswered message time), lock or archive, session disconnect (GM-12) or a
   moderator (GM-16).
6. At most one open message per author per topic (GM-09). The first message of a topic is
   never open (GM-14).
7. Notifications, unread counts and search treat a growing message as one item (GM-13).

The engine is `Idejo.Messages`: the composer sends the author's whole message after each Enter
and `commit/4` stores it (`break: true` for Ctrl+Enter), adding `.` after unpunctuated text
(not after code). Each commit overwrites `body_md`/`body_html`; one that changes text already
sent first keeps the old text in `message_versions` (GM-11). History is kept only for edits
(TP-05): a message that only received appends keeps just its final text, with no versions and
no per-commit rows. Events go to `"topic:{id}"` on `Idejo.PubSub`: `{:message, message}` and
`{:window_ended, id}`. The window length is the `gm_window_seconds` setting (default 15,
2–600 s; steward decision, 2026-10-23), set in **Admin → Settings** (GM-15, AD-04; server-wide
only in v0.1, no per-category override); a change applies to messages opened after it. The
**unanswered message time** (`gm_unanswered_minutes`, default 10, 1–1440; steward decision,
2026-10-23) holds Ctrl+Enter back further: while no message (not deleted) is below the open
one, it closes only once `opened_at` is that old (`Messages.may_start_new?/2`,
`unanswered_until/1`; read at each Ctrl+Enter, so a change applies to open messages too);
until then Ctrl+Enter appends like Enter. `TopicLive` works it out from the messages shown
for the composer's description (AX-03), with no query. Tests
set `recover_open_messages: false` and call `Idejo.Messages.Recovery.run/0` themselves.

### Permissions

Roles (RP-01): the built-in roles owner, administrator, moderator, member and guest are created
by migration; a database trigger refuses to delete, rename or un-built-in them. Lower
`position` ranks higher. Guest and member are implicit, never stored in `user_roles`: visitors
and users with an unverified email act as guest (an unverified owner or administrator keeps
that role too); every verified user holds member on top of their other roles
(`Idejo.Access.roles_of/1`). Nobody is ever without a role.

Role editor (RP-02, **Admin → Roles**): custom roles have a name (unique ignoring case, also
against built-in names) and an optional `#rrggbb` colour, and can be renamed, moved one place
up or down, and deleted. Built-in roles only change colour, "Visible next to name" and,
except member and guest, their mention settings (TP-10). Owner and administrator stay on
top and guest stays last (`Access.movable?/1`). Every change is audited (`role.create`,
`role.update`, `role.reorder`, `role.delete`). A role's name is written in its colour, grey
without one (steward decision, 2026-10-23): always `Admin.role_label/1`, whose `role-{id}`
class gets `--role` from `Layouts.role_colours/1` (one nonce `<style>` in the root layout)
and, on admin pages, from the `RoleColours` hook (`data-role-colour`, set through the DOM),
so a colour just changed shows; never a `style` attribute (SP-05). Any role, built-in too,
can turn off "Visible next to name" (`roles.show_next_to_name`, default on): conversations
show the author's highest visible role (`Access.shown_role/1`), the role keeps its rights.

Role assignment (RP-06, **Admin → Users → a user**): `Access.assign_role/3` and
`Access.unassign_role/3`, audited as `role.grant` / `role.revoke`. Only owners give or remove
the owner role (steward decision, 2026-10-19); guest and member are never given. Removing
refuses the last owner and an administrator's own administrator role. When a user stops being
an administrator, their sessions' LiveViews are disconnected so open admin pages re-check.
The name colour is the colour of the highest-ranked role that has one (`Access.name_colour/1`,
`Admin.coloured_name/1` in the admin users list and page).
`Access.grant_role/2` (unaudited) is only for setup and test fixtures.

Self-select roles (steward decision, 2026-10-23): owners and administrators mark custom roles
"Members can choose it" (`roles.self_select`, never on built-in roles; any rights the grid
gives such a role go to whoever picks it, which the role editor warns about). Members set
theirs with `Access.set_self_roles/2`, which only adds or removes self-select roles (audited
as `role.self_grant` / `role.self_revoke`, by the member). A new member sees the welcome
card once (`Layouts.app`, while `users.welcomed_at` is nil; existing members, the setup
wizard's owner and test fixtures are marked welcomed; `user_fixture(%{welcome: true})` is
not): About and Rules (`server_about`, `server_rules` settings, Markdown, through
`MessageComponents.body/1`) and the roles, a plain form to `POST /welcome`
(`WelcomeController`, which also marks the card seen). `/rules` ("Rules & Roles" in the
sidebar) shows the same at any time (`IdejoWeb.WelcomeComponents`).

Every read and write goes through `Idejo.Access.can?(user, right, category)`. Rights in v0.1:
`:view`, `:start`, `:post`, `:moderate`, and `:tag` (edit a topic's tags, TP-19). Each role's right on a category is allow, deny or
unset; unset follows the role's server-wide setting (a `category_permissions` row with no
`category_id`), and deny overrides it (RP-04/RP-05). Across roles, **allow wins**: a right is
granted when any of the user's roles allows it, even if a higher-ranked role denies it (RP-06).
Search and lists filter by `:view` in the query, never after loading: use
`Idejo.Access.where_allowed(query, user, right)` for lists and `Access.can?/3` for one
category. Settings change only through `Access.set_permission/5` (audited as
`permission.update`). Server-wide defaults seeded at install: guest views; member views,
starts topics and posts; moderator also moderates and edits tags (`:tag`, TP-19).
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
  Files that cannot hold comments are covered in `REUSE.toml`. `LICENSE`, `NOTICE` and
  `LICENSES/` ship at the root of every release (`copy_licence/1` in `mix.exs`, and the
  Dockerfile copies them into the build).
- **Tests per requirement** (DV-02): name the test after the ID and tag it.
  ```elixir
  @tag req: "GM-03"
  test "GM-03 appends never extend the window" do
  ```
  `test/idejo/requirements_test.exs` enforces it: every MVP ID (read from the MVP sheet's
  requirements table by `Idejo.Requirements`) has a tagged test, each tagged test starts with
  its ID, and every tagged ID exists in a sheet. IDs whose tests come with a later PR are in
  its `@pending` (remove the ID when its tests land, or the test fails); process-only IDs
  (DV-05, LI-08) are in `@by_review`, and NF-04, checked by the load test, in
  `@by_load_test`. Requirements met by repository files (SP-01, LI-01,
  DV-01, DV-03, DV-04, DV-06) are tested in `test/idejo/repository_test.exs`.
- **Async tests and shared rows**: async tests run side by side, each in its own sandbox
  transaction, and a lock taken there lasts until the test ends (`Forum` locks categories,
  `Access` locks roles). So in async tests: give unique columns values of their own
  (`unique_username/1`, `unique_role_name/1` in `AccountsFixtures`; never a fixed username or
  role name), and make a module `async: false` when it writes rows every test shares (built-in
  roles, settings) outside the contexts. Every change to roles takes `Access`'s roles lock
  first, every change to categories `Forum`'s, so locks are always taken in the same order.
- **End-to-end flows** (MVP §4, §8): one test per flow in `test/idejo_web/flows/`, driving the
  real pages in order with ConnTest and LiveViewTest (no browser), tagged
  `@tag flow: "admin-sets-up-the-server"` etc.
- **No third-party scripts, fonts or analytics** (SP-04). Assets are served from the app.
  Fonts (steward decision, 2026-10-23): Fraunces for titles (`--font-title`: headings and
  title-like classes) and Rubik for text (`--font-body`), WOFF2 subsets from Fontsource in
  `priv/static/fonts/` with their `@font-face` rules at the top of `app.css` (OFL-1.1,
  credited in `NOTICE` and `REUSE.toml`). Small uppercase labels stay in Rubik.
- **Server stylesheet** (steward decision, 2026-10-23): the `custom_css` setting, default
  `priv/theme/default.css` (`Settings.default/1`), edited in **Admin → Stylesheet**
  (`Admin.StylesheetLive`: save, reset to default; audited like any setting) and served at
  `/theme.css` (`ThemeController`, no session, `text/css`, `nosniff`), linked by the root
  layout after `app.css` with `?v=` and a hash of its text (cached for good; the bare address is
  revalidated). The default makes `.modal-box` cards 70% opaque with a 3px backdrop blur and
  the welcome card 80% with 6px, as variables.
- **No inline `<script>`, `<style>` or `style=""`** — the content security policy refuses them
  (SP-05, `IdejoWeb.Plugs.ContentSecurityPolicy`). Put code in `assets/js/` and styles in
  `assets/css/`; a dependency that needs inline code gets the per-request nonce from
  `conn.assigns.script_csp_nonce` / `style_csp_nonce`.
- **Accessibility** (AX-01, `docs/accessibility.md`): every page has a skip link to
  `<main id="main">` first, one `<h1>`, no skipped heading level, named `<nav>`s, labels and
  names on every control, and a visible `:focus-visible` outline (never `outline: none`
  without a replacement). `test/idejo_web/accessibility_test.exs` audits every page with
  `IdejoWeb.Accessibility.audit/2` (`test/support/accessibility.ex`): add new pages to its
  lists. When markup that has the focus is replaced (an editor opening or closing), move the
  focus on purpose (`phx-mounted={JS.focus(...)}`, as `TopicLive` does with `refocus`). The
  editor's Write / Preview tabs follow the ARIA tabs pattern (`EditorTabs` hook). Screen
  readers are checked by hand before a release (checklist in the doc).
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
  never changes (@mentions). The same page sets and removes the avatar
  (`Accounts.set_avatar/2`, `remove_avatar/1`, with an `update` activity carrying `icon`):
  `Uploads.store_avatar/2` makes a 256 px WebP square without metadata, so its URL is
  `/uploads/<avatar_id>.webp` (`Uploads.avatar_url/1`, no preload needed); a replaced picture's
  file and row are deleted. Show users with `UserComponents.avatar/1` (picture or initial,
  decorative). A second, optional picture for the dark theme (`users.avatar_dark_id`,
  `Accounts.set_avatar(user, path, :dark)`, `remove_avatar(user, :dark)`,
  `Uploads.dark_avatar_url/1`; steward decision, 2026-10-23) is set under "Dark mode
  picture", a `<details>` folded until one exists; `avatar/1` then renders both images
  (lazy, `.avatar-has-dark`) and the stylesheet shows the theme's; with one picture only,
  both themes show it. The same page changes the password (AC-01, below).
- **Deleting an account** (AC-07): `Accounts.delete_user/2`, from the profile with the
  password. The row stays (its `uri` and the records naming it keep working) but is
  anonymised: placeholder email and username that sign-up can never produce, "Deleted user",
  random password, roles, tokens, links and avatar deleted, `status: "deleted"`, and a
  `delete` activity. `Access.ensure_not_last_owner/1` refuses the last owner.
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
  Category groups (steward decision, 2026-10-23; `Idejo.Forum.CategoryGroup`,
  `categories.group_id`): named, ordered, managed in the same page (`category_group.*`
  audited; group changes take the categories lock, then the groups lock). The home page and
  the sidebar show `Forum.sections/2`: one "Categories" section, or with two or more sections
  each group's name over its categories and the ungrouped last as "Other".
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
- **Posting and inline replies** (TP-08): members post with the composer (`Messages.commit/4`);
  `Forum.post_message/3` still posts one closed message (tests use it). Both need
  `Forum.can_post?/2` (the `:post` right and an open topic; locked and archived take nothing).
  A reply's `reply_to_id` must be a message of the same topic, set when the reply opens
  (only moving messages, TP-15, leaves replies across topics);
  replies stay in the one flow, shown with `Forum.excerpt/2` linking to `/m/{id}`. "Reply"
  links use `?reply_to={id}#composer`, so choosing a message needs no JavaScript.
- **Live updates stay cheap** (NF-01): `Messages.broadcast/2` sends `{:message, m}` with
  `Messages.shown/0` loaded once; a topic view must do no database work per update (every
  viewer handles every Enter). Keep it so: check with `load/run.sh --hot --writers 10`
  (p95 within 200 ms) and `load/top.exs`.
- **Live topics** (TP-04): the topic page stays a controller and embeds `IdejoWeb.TopicLive`
  (`live_render/3`, session `"topic_id"`, `"reply_to_id"`) for every viewer: the message list
  (a keyed comprehension, `#message-{id}`, kept for permalinks) and the composer for posters.
  Its first render is in the page's HTML (no JavaScript needed to read). Connected, it subscribes before
  loading; `{:message, m}` events update in place or append; a reconnect mounts again, which
  is the catch-up. Anything that changes a message must broadcast it after its transaction.
  Rights are checked at mount and again on `:permissions_changed`, which
  `Access.set_permission/5` broadcasts after a grid change (`Access.subscribe_permissions/0`;
  steward decision): a viewer who lost `:view` sees the list emptied and gets no more events.
- **Composer** (GM-02, GM-07, GM-08): in `TopicLive`, the author's open message in place
  (messages before it, the composer under the author's name, later replies below; at the end
  when nothing is open). Only a text box whose placeholder names the keys: no button or
  status, and no box (steward decision, 2026-10-23), but a thin orange line under it
  (`#composer-timer`, `ComposerTimer` hook, `aria-hidden`; steward decision, 2026-10-23)
  that fills up until Ctrl+Enter may start a new message (the window's end, or the
  unanswered message time's while nobody wrote below: `start_new_at/3`), its front glowing
  white in yellow, then burns in and goes; the hook sets its duration and negative delay
  through the DOM, from the server's `data-start` / `data-end` / `data-now`. Sent text is drawn like a
  message's, unsent text highlighted with box-shadow only (the backdrop must keep every
  character under the transparent textarea), and text just sent "burns" in
  (`.composer-burn`, `BURN_MS`; `burnMarks/2`; repaints keep its place with a negative
  `animationDelay` set through the DOM, never a style attribute). A faint ring shows the
  focus (AX-01). The `Composer` hook (`assets/js/composer.js`) pushes `"commit"`
  (`body`, `break`) and keeps the text; its `finishSentence/1` must match the server's dot
  rule. `data-sent` and the `"composer_sent"` push restore the open message after a reload
  or reconnect; the text box is `autocomplete="off"`, and what a browser still puts back on
  reload is cut to what followed the sent text (`keptAfterReload/2`), so the message never
  shows twice. Three Enters in a row, nothing typed between and each within 1 s of the last,
  work as Ctrl+Enter (`enterRun()`, `ENTER_RUN_MS`; steward decision, 2026-10-23), on touch
  screens too, which have no Ctrl.
- **Composer commands** (steward decision, 2026-10-23): after `!` at the start of a word the
  `Suggest` list shows the composer's commands (`data-commands` from `TopicLive.commands/2`:
  only those the author may use; no server question; Enter picks one only once a letter
  follows the `!` or an arrow chose it). Picking one removes what was typed and runs it:
  `!image` clicks the composer's file input and the image's Markdown goes at the end
  (`appendLine/2`); `!new-topic` sends with `then: "new_topic"` (or pushes `"new_topic"` with
  nothing new: the open message), and `TopicLive` redirects to
  `/m/{reply_to_id || message id}/new-topic?from={message id}`, where `NewTopicLive` fills the
  first message with the author's own message (TP-09); `!schedule` pushes `"open_schedule"`
  with the text not sent yet (never sent text: nothing when sent text was changed), and the
  dialog (`#schedule-dialog`, `InlineCard` hook) asks for hours; `!poll` and `!spoiler`
  send what is new with `then: "poll"` / `"spoiler"` (or push `"open_poll"` / `"spoiler"`
  for the open message; nothing open asks for the message first). The commands are defined
  once, in `IdejoWeb.ComposerCommands` (`all/0`; `for_composer/2` filters them for the list).
- **Polls** (steward decision, 2026-10-23; `Idejo.Messages.Polls`, `polls`, `poll_options`,
  `poll_votes`): `!poll`'s dialog (`PollComponents.poll_dialog/1`, `#poll-dialog`) takes a
  question, 2 to 10 answers, "Allow several answers" and hours like `!schedule` (required,
  at most 168), for the author's message (one poll each, `create/3`). `PollComponents.poll/1`
  shows it under the message (under the composer for the author's open message): a form
  posting `"vote"`; anyone with the post right votes (`Forum.can_post?/2`, not on deleted
  messages), changes or takes back their vote until `closes_at`. Votes are anonymous; counts
  (`<progress>` bars) show to voters, the author and, once closed, everyone
  (`results_shown?/4`). `{:poll, message_id, summary}` goes to the topic after each change,
  worked out once (NF-01); `Idejo.Messages.PollWorker` (queue `messages`) sends it again at
  `closes_at`. Votes are rate-limited (`:vote`).
- **Spoilers** (steward decision, 2026-10-23; `messages.spoiler`,
  `Messages.set_spoiler/3`, author only, open messages too, broadcast as `{:message, m}`):
  `TopicLive` covers the body and poll with `.spoiler-cover` (50% opacity, 4px blur) and a
  "Reveal spoiler" button (80%, 6px; the variables are in `priv/theme/default.css`), the
  content `inert` until the viewer reveals it (`"reveal_spoiler"`, per view). Only once
  connected: without JavaScript there is no cover and no `inert`. `Forum.excerpt/2` and
  search excerpts read "(spoiler)".
- **Help** (steward decision, 2026-10-23): `/help` (`HelpController`, public, no JavaScript),
  linked in the sidebar under Rules & Roles (`#help-link`): the keys that send (with this
  server's window), the signs `@ + # / $ !`, and every command from
  `ComposerCommands.all/0`. A change to the keys, the signs or the commands updates it.
- **Scheduled messages** (steward decision, 2026-10-23; `Idejo.Messages.Scheduling`,
  `scheduled_messages`): up to 168 hours, decimals allowed (`parse_hours/1`, at least a
  minute), with the post right now. One Oban job each (`Idejo.Messages.ScheduledWorker`, queue
  `messages`, `scheduled_at`). Only the author sees them, under the composer
  (`#scheduled-messages`, Cancel: `cancel/2`). At its time `post/1` posts it with
  `Forum.post_message/4` (`scheduled: true`, closed: it never grows), as the author, rights
  checked again; a refused one (locked, no right, banned or deleted account) is dropped,
  `:rate_limited` snoozes. Each change broadcasts `{:scheduled, author_id}`; readers see
  "scheduled message" (`messages.scheduled`) next to "view earlier version" (`.message-meta`).
- **Assistive text** (AX-02, AX-03, GM-07): the open state is never visible, only text.
  `TopicLive` has one hidden live region (`#topic-announcer`, `role="status"`) that announces
  a message when it opens and when it closes (or once, when posted closed), never at appends
  or edits; the message list is never `aria-live`. Open messages carry an `sr-only` "(still
  being written)". The composer's text box is `aria-describedby="composer-window"`: the open
  state and the time left in the window, re-rendered by a one-second `:tick` while the
  viewer's own window runs and on `{:window_ended, id}`.
- **Long messages** (GM-06): no size limit anywhere (no length validation on bodies). In
  `TopicLive` bodies use `MessageComponents.collapsible_body/1`: the `ShowAll` hook
  (`assets/js/show_all.js`) collapses a body taller than the window, with a "Show all" button,
  and re-measures growing messages. Its state lives in `data-collapsed` / `data-expanded`, kept
  across patches by `JS.ignore_attributes`. Without JavaScript the whole body shows.
- **Edits and earlier versions** (GM-10, GM-11): open messages are edited in the composer;
  closed ones with `Messages.edit/3` (the author only, in an open topic; the text kept as
  written, no `.` added), from an "Edit" button that opens the message editor in place.
  Changing text already there keeps a version and sets `edited`; adding at the end does not.
  Edited messages, open or closed, show a "view earlier version" `<details>` (no JavaScript
  needed) listing each version newest first with the span it was current. `list_messages/1`
  preloads `:versions`.
- **Deleting one's own message** (steward decision, 2026-10-23): saving an edit with no text
  asks "Are you sure you want to delete your own message?" (`TopicLive`, `confirm_delete`;
  "No" is a `method="dialog"` form, so the focus returns to the editor), and "Yes" calls
  `Messages.delete_own/2`: like a moderator's delete (MO-02: `deleted_at`, the topic counts
  one less, kept for moderators) but `deleted_by_id` is the author, nothing is logged, and
  the topic's opening message is refused (it stays "can't be blank"). Readers see "Message
  deleted by user" (`Messages.deleted_by_author?/1`; runs of deletions are grouped by kind).
- **Closing** (GM-12, GM-16): archiving topics closes their open messages
  (`Messages.close_open_in_topics/1` inside the transaction, `announce_closed/1` after it);
  locking (TP-14, `Forum.moderate_topic/4`) does the same. `Idejo.Messages.Authors` tracks live topic views
  (`present/2`, called by `TopicLive`); when a user's last view of a topic is gone for the
  grace (30 s, `:gm_disconnect_grace_ms`; steward decision) their open message there closes.
  `Recovery` starts that grace for every open message at boot. Moderators close others' open
  messages (`Messages.close_as_moderator/3`, a "Close message" button; logged, MO-03). Tests run with a
  one-hour grace and pass `grace_ms:` when they need one.
- **Topic list** (TP-03): the category page lists `Forum.list_topics/2`, 30 a page (`?page=`),
  pinned first, then by `last_activity_at`, with starter, message count, last activity and,
  for signed-in users, the unread marker ("N new"). Every topic list (category, home,
  `/unread`) renders rows with `TopicComponents.topic_row/1`; the title link stays a direct
  child of the `<li>` (tests read `#topics li > a`). The home page's active topics pass
  `lead={:category}`: the category's mark and name instead of the starter's avatar and name.
  Its tags sit at the right, above the message count (steward decision, 2026-10-23).
  **View** (steward decision, 2026-10-23): the home page (beside its first section title)
  and the category page (beside its `<h1>`) carry `TopicComponents.view_toggle/1`, two links
  (`?view=compact`, the default, and `?view=expanded`) remembered in the session
  (`IdejoWeb.TopicView`). Expanded rows get `preview=` from `Forum.topic_previews/1` (a few
  queries per page, whatever its length): the opening message's excerpt (`Forum.excerpt/2`,
  so spoilers stay hidden) and its first `/uploads/` image at the right, "Latest messages"
  (not a heading: AX-01) over a line with the three latest other messages, and the writers'
  avatars, five and "+N more" past six. Deleted messages are left out.
- **Unread** (TP-07, `Idejo.Reading`): one `read_positions` row per user and topic, holding
  the last message seen. Opening a topic (`TopicController`, and `TopicLive` on connect)
  marks it read with `Reading.mark_read/2`, and so does every new message arriving while it
  is open (steward decision); appends do not move it. Unread = messages by others opened
  after that message (`opened_at`), so a growing message counts once and never turns unread
  again as it grows (GM-13). Without a position, everything before the user's sign-up is
  read. `/unread` (`UnreadController`, signed in, linked from the header) lists topics with
  unread messages across viewable categories: on the first page, "Following" holds every
  followed one (`Reading.list_unread_followed_topics/1`, `#followed-topics`; steward
  decision, 2026-10-23), then "Other topics", 30 a page (`Reading.list_unread_topics/2` with
  `following: false`, `#topics`). The header's Unread link (`Layouts.unread_link/1`) carries
  a dot counting unread messages that reply to the user or @/+ mention them
  (`Reading.for_you/1`, view right in the query; steward decision, 2026-10-23), coloured
  like the sidebar's dots (`.unread-badge.is-{level}`); `/sidebar` serves the link too, so
  the `Notifier` hook keeps the count current.
  Where one left off (steward decision, 2026-10-23): `TopicController` asks
  `Reading.first_unread/2` (nil without a read position) before `mark_read/2` and passes it
  to `TopicLive` (session `"first_unread"`), which draws the red "N unread messages" line
  (`#unread-line`, `.unread-line`; not `.unread-marker`, the lists' "N new") in that
  message's `<li>`; the `UnreadLine` hook (`assets/js/topic_nav.js`) centres the page on it
  unless the address has a `#`, CSS fades it after 4 s and `"unread_line_done"` drops it.
- **Topic navigator** (steward decision, 2026-10-23): `TopicLive`'s `#topic-nav` (named
  `<nav>`), links to `#message-{id}` of the first message, the first unread, the last and the
  reader's last (not deleted). The `TopicNav` hook shows it once the page's `<h1>` is under
  the header: a card at the right when the space beside `#main > div` fits it, else a pill
  at the top right that opens it (`data-shown`, `data-mode`, `data-open`, kept by
  `JS.ignore_attributes`); a jump centres the message and focuses its first control.
  Hidden without JavaScript.
- **Images** (TP-12, `Idejo.Uploads`, extra review: DV-06): JPEG, PNG, GIF and WebP only,
  decided by libvips from the content (`image` + `vix`, precompiled libvips; LI-06 checked),
  re-encoded in the same format without metadata (SP-05), animated frames kept, JPEGs turned
  upright, at most 40 megapixels and `upload_max_mb` (default 3, **Admin → Settings**).
  Stored in `:uploads_dir` (`IDEJO_UPLOADS_DIR`, the `/data/uploads` volume in production;
  `tmp/test_uploads`, emptied by `test_helper.exs`, in tests) as `<id>.<ext>`, with an
  `uploads` row; served by `UploadController` at `/uploads/<id>.<ext>` without a session, to
  anyone with the link (steward decision), `nosniff`, cached for good. LiveViews take images
  through `IdejoWeb.ImageUploads` (`allow/3`, `check/2` in `phx-change`): paste or drop into
  the composer (`composer_image`, hidden input, no button: GM-07) or the editor
  (`EditorImages` hook), plus the editor's "Add image" picker; `"image_uploaded"` brings the
  Markdown back to the caret, unsent. Tests make images with `Idejo.ImageFixtures`.
  Uploads nothing uses (inserted, then removed before sending; avatars never set) are deleted
  with their files at 04:00 UTC (`Idejo.Uploads.CleanupWorker`, queue `maintenance`) once a
  day old: `Uploads.delete_unused/1` keeps avatars and every `/uploads/<name>` named in
  `body_md` of messages (deleted ones too) and `message_versions`, or in a setting. A new
  place that can name an upload must join its query.
- **Search** (SE-01 to SE-03, `Idejo.Search`): PostgreSQL full text with the `'simple'`
  configuration (steward decision). `messages.search_vector` is a generated column over
  `body_md` with `<` and `>` read as spaces (else the parser drops words inside `<script>`),
  so every commit re-indexes a growing message; titles use an index on
  `to_tsvector('simple', title)` and are found through the topic's first message. Queries use
  `websearch_to_tsquery`; results are filtered by view right in the query and optionally by
  category. Excerpts come from `ts_headline` with `\x01`/`\x02` markers split into segments
  (`Search.excerpt/1`), never raw HTML. `/search` (`SearchController`, public, GET form, no
  JavaScript), linked from the header.
- **Notifications** (NO-01, NO-02, `Idejo.Notifications`, in-app only): one `notifications`
  row per user and message (`kind`: mention, reply, role_mention, follow; older `reaction`
  rows stay unused). A new message notifies the users it @mentions, the author it replies
  to, the members of the roles it +mentions (`role_mention`, steward decision, 2026-10-23)
  and the topic's followers, in that priority, never its author or anyone who may not view
  the topic (`notify_new/2`); an append or an edit notifies only someone newly mentioned,
  turning their earlier notification for that message into an unread mention when that
  ranks higher (`notify_mentions/2`). Both run inside the transaction that writes the
  message; any new way of writing a message must call them. They are shown as the
  sidebar's dots on followed topics (`Reading.activity/2`) and as live bubbles: there is no
  notifications page or bell (steward decision, 2026-10-23, departing from MVP §5's
  Notifications screen), and `read_at` is no longer set.
- **Email summary** (steward decision, 2026-10-23, with NO-04 of the v1 sheet:
  `Idejo.Notifications.Digest`, `email_preferences`, `Idejo.Notifications.DigestWorker`,
  Oban cron hourly, queue `maintenance`): the profile's "Email notifications" section
  (`UserSettingsLive`, `Digest.update_preferences/2`; no row means the defaults: mentions
  and replies and own topics on, once a week on). `users.last_seen_at` is kept by
  `Accounts.seen/1` from `UserAuth.fetch_current_scope_for_user/2`, writing at most every
  five minutes. After 24 hours away a member gets one email counting, for each chosen
  option, what happened since they were seen or since the last summary: closed messages
  only (NO-04), not deleted, by others, viewable, not in muted topics; nothing to count
  sends nothing. Once a week: no second one for seven days while away (the email says so);
  else one a day. Every email carries `List-Unsubscribe` (+ `-Post`, RFC 8058) to
  `/email/unsubscribe/{token}` (`EmailUnsubscribeController`: GET page in `:browser`, POST
  outside it, no session or CSRF: the random token is the authority), which turns every
  option off.
- **Live notifications** (steward decision, 2026-10-23): what `notify_new/2` and
  `notify_mentions/2` insert waits in the writing process (process dictionary) until
  `Notifications.announce/1` after commit: `Messages.broadcast/2` calls it for every
  `{:message, m}` (so every message write must broadcast after its transaction, as it
  already must), `Forum.create_topic/4` for a topic's first message; entries of another,
  failed, transaction are dropped. Each goes to `"user:{id}"` as `{:notification, live}`,
  and `Notifications.announce_reaction/3` sends one for a reaction (nothing stored). The
  root layout renders `IdejoWeb.NotifierLive` for signed-in users, outside the page's main
  LiveView (live navigation keeps it); it pushes each as `"notification"` to the `Notifier`
  hook (`assets/js/notifier.js`): bubbles at the top right (`.bubble.is-{kind}`, the dots'
  colours, purple for reactions; 10 s, paused while pointed at or focused; newest on top,
  three at most; none for the topic on screen, `#topic-live[data-topic-id]`), and the
  sidebar fetched again from `/sidebar` (`SidebarController`, `Layouts.sidebar/1`) after a
  notification, when the tab comes back, and every 5 s for the first 20 s after a page
  loads (live navigation included), then every 30 s, then past 5 min every 10 min, never while it has the focus,
  keeping `<details>` open or folded by id.
- **Inline links** (TP-10; steward decision, 2026-10-22, replacing "@user only"): every body
  renders through `Idejo.Messages.Body.to_html/2` with its context (`author:`/`author_id:`,
  `category_id:`/`topic_id:`, or `Body.context(message)`; messages, previews, versions),
  never `Idejo.Markdown.to_html/1` directly. `Markdown.references/1` finds, outside code and
  links, `@username` (→ `/u/{id}`), `+role` (the role's name as a slug, `Access.role_slug/1`,
  → `/r/{slug}`), `#slug` (a topic → `/t/{id}`: the one the author last wrote in, else the
  most recently active), `/slug` (a category → `/c/{slug}`) and `$slug` (a tag →
  `/tags?tags[]=slug`), resolved as the author may view them; unknown ones stay text. Links
  read the name (`#Garden plans`, `+Moderator`) unless it lives where some readers may not
  look (only names guests may view, or of the message's own category), then the slug as
  typed. Highlighted by `a[href^=…]` in `.message-body` (the sanitiser keeps no classes).
  `+role` works only for roles the author may notify (`Access.mentionable_roles/1`): roles
  with `mentionable` ("Can be tagged by everyone"), and roles ranked below one of the
  author's roles with `mentions_below` ("Can tag roles beneath"); owners and administrators
  any; never member or guest. Both settings are on for owner, administrator and moderator
  by migration, edited in **Admin → Roles** (audited in `role.update`). Notifications:
  `Body.mentioned_users/1` and `Body.mentioned_role_members/2` (members who may view get a
  `role_mention`); an @mentioned user, or a member of a +mentioned role (steward decision,
  2026-10-23), who may view the topic also follows it (`auto_follow`, so an explicit
  unfollow stays). `/r/{slug}` (`RoleController`, public) lists a role's members.
  **Suggestions while typing**: after `@`, `+`, `#`, `/` or `$` at the start of a word, the
  composer and the message editor show a list (`assets/js/suggest.js`: the `Suggest` class,
  used by the `Composer` hook before its own Enter handler, and the `EditorSuggest` hook; an
  ARIA combobox on the text box with a `role="listbox"` `<ul>` beside it). The LiveView answers
  `"suggest"` (`sign`, `q`) with `IdejoWeb.Suggestions.reply/3`, from
  `Idejo.Suggestions.suggest/4`: recent items first (people who wrote in this topic, then in
  the topics the user last read; the topics, categories and tags of those topics; roles the
  user may tag, by rank), then the rest matching by name or slug, at most 8, filtered by view
  right in the query. Click, or arrows and Enter/Tab, inserts the username or slug and a
  space; Escape closes.
  `/u/{id}` (`UserController`, public) shows the user card (`UserComponents.user_card/1`:
  avatar, display name, username, roles).
  **Cards**: in a topic, the `InlineLinks` hook (`assets/js/inline_cards.js`) turns a click on
  a link in a message body that names a user, role, topic, category or tag into
  `"show_card"` (`kind`, `ref`); `IdejoWeb.InlineCards.load/4` builds the card for the
  reader and `TopicLive` shows it in one `<dialog id="inline-card">` (`InlineCard` hook,
  `"hide_card"`; `IdejoWeb.CardComponents.inline_card/1`, heading `#inline-card-name`): a
  preview, a link to open it, and an action (user actions for server moderators, Follow /
  Unfollow on a topic via `"card_follow"` / `"card_unfollow"`, New topic in a category). A
  reader who may not view it gets `%{shown: false}` and the browser follows the link.
- **New topic from this** (TP-09): every message has a "New topic from this" link for users
  who may start a topic somewhere (`Forum.list_startable_categories/1`). It opens
  `NewTopicLive` at `/m/{id}/new-topic` (`:fork`): the source's excerpt and a category choice.
  `Forum.create_topic/4` with `forked_from: message` sets `topics.forked_from_message_id`
  (needs view of the source and `:start` in the target), adds `forkedFrom` to the activity and
  broadcasts `{:forked, message_id}` to the source topic. The new topic's page shows
  "Continued from …"; the source message shows a "Continue topic" button per topic
  (`Forum.list_forks/2`; its title in the name; steward decision, 2026-10-23). Both only when
  the viewer may view the other topic.
- **Topic menu** (steward decision, 2026-10-23): right click, the menu key or a long press
  on a topic row (`TopicComponents.topic_row/1`) or a sidebar topic (`data-topic-menu`,
  `data-topic-path`; the sidebar's `data-following` tells Follow from Unfollow) opens
  `Layouts.topic_menu/1` (`#topic-menu`, `role="menu"`, `phx-update="ignore"`, signed-in
  users only) at the pointer (`assets/js/topic_menu.js`: arrows, Escape, focus back). Its
  items are plain forms with `return=back`: unfollow, follow, `POST /t/{id}/mute`
  (`Reading.mute/2`) and `POST /t/{id}/unread` (`Reading.mark_unread/2`: the position goes
  back before the latest message by someone else), and Copy link. **Muted** (`follows.muted`,
  with `following: false`): `Notifications` never notifies a muted user (`may_view/2`, and no
  reaction bubble), `Reading.for_you/1` and `list_unread_topics/2` leave it out, and only
  `Reading.follow/2` lifts it. **Every menu is a `.popup-menu`** (the account panel too): one
  surface in `app.css`, see-through and blurred by `--menu-opacity` / `--menu-blur` (70%,
  4px) from the server stylesheet (`priv/theme/default.css`); a new menu takes the class.
  The header's glass is its `::before`, so menus in it blur the page under them.
- **Follow** (TP-13, `Idejo.Reading`): `follows` rows (user, topic, `following`). Starting a
  topic or posting in it follows it (`Reading.auto_follow/2` inside the transaction that
  writes the message); an explicit unfollow stays as `following: false`, so posting again does
  not undo it (steward decision: followers get notified of new messages, with NO-01). The
  topic page has Follow / Unfollow forms posting to `/t/{id}/follow` (`FollowController`,
  POST / DELETE, no JavaScript needed). Topics followed by everyone (steward decision,
  2026-10-23): owners and administrators mark them on the topic page
  (`Forum.set_autofollow/3`, audited `topic.autofollow`; `TopicAutofollowController`, POST
  `/t/{id}/autofollow`); a user without a `follows` row for one follows it (members who
  join later included: nothing is copied), an unfollow row still holds, and visitors' sidebars
  list the ones they may view, without × or +. `Reading.following?/2`,
  `list_followed_topics/1`, the Unread page and `Notifications` followers (every active user
  who did not unfollow, then filtered by view) all read it.
- **Tags** (TP-19, `Idejo.Forum.Tags`, `Idejo.Forum.Tag`; steward decision, 2026-10-22:
  built in M5 though the MVP sheet defers tags): administrators make them in **Admin → Tags**
  (`Admin.TagsLive`), server-wide (`category_id` nil) or for one category (never the Archive),
  rename and delete them, audited as `tag.create|update|delete`. Names are unique across the
  server ignoring case; the slug is made at creation and kept. A category offers the
  server-wide tags and its own (`Tags.available_tags/1`); `Forum.create_topic/4` takes
  `tag_ids` and needs at least one when the category offers any (`change_new_topic/2`), and
  the topic's `create` activity carries `tag`. A topic's tags change through
  `Forum.set_topic_tags/4`, which needs the `:tag` right ("Edit tags" in the grid, allowed
  server-wide for the built-in moderator by the migration), refuses archived topics, and is
  logged as `topic.tags` (MO-03) with an `update` activity; the topic page's "Edit tags"
  form posts to `/t/{id}/tags` (`TopicTagsController`, no JavaScript). Moving a topic drops
  the old category's own tags (`Tags.drop_foreign_tags/2`); deleting a category deletes its
  tags. Topic lists preload `tags: Tags.ordered()` and show them with
  `TopicComponents.tag_list/1` (links in a `<p>`, never `<li>`s, so `#topics li > a` stays
  the titles), each linking to "Filter by tag": `/tags?tags[]=slug` (`TagController`,
  public GET form, no JavaScript), topics carrying **all** chosen tags
  (`Tags.list_tagged_topics/3`), filtered by view right in the query, 30 a page.
- **Message editor** (TP-02): `MessageComponents.editor/1`, a Markdown text box with Write /
  Preview, used for every message (the first message now, replies and the composer later).
  Nothing typed is stored or sent before posting; the preview is rendered for the author only.
- **Deleting a category with topics** (RP-03, TP-14): `Forum.delete_category/3` needs
  `topics: {:move, target}` or `topics: :archive` (else `{:error, :has_topics}`). Archived
  topics go, read-only (`state: "archived"`), to the one Archive category (`archive: true`),
  made on first use by `Forum.archive_category/1` with a `:view` deny for every role; admins
  show it to roles in the grid. The Archive is never deleted and takes no new topics
  (`Forum.can_start_topic?/2`).
- **Emoji** (TP-17; steward decision, 2026-10-22): `Idejo.Emoji` knows the GitHub/Slack names
  (gemoji, MIT, `priv/emoji/emoji.json`) and draws them with Twemoji SVGs vendored in
  `priv/static/emoji/` (CC-BY 4.0, credited in `NOTICE` and `REUSE.toml`; never a CDN:
  SP-04), plus the server's own reactions in `priv/static/reactions/` (`:agree:`, `:bruh:`…,
  the steward's, CC-BY 4.0). How to update them: `priv/emoji/README.md`. `Markdown.to_html`
  turns `:name:` and typed emoji into `<img>` outside code (alt: the emoji, or `:name:`);
  `Forum.excerpt/2` reads them back as their alt. Image addresses carry `?vsn=` with a
  hash of every image (`Emoji.version/0`, worked out at compile time), so `Plug.Static`
  caches them for a year (stored message HTML keeps the version it was written with; the
  files stay, so old addresses keep working).
- **Reactions** (TP-17, `Idejo.Reactions`): `reactions` rows (message, user, emoji name),
  several emoji per user. `toggle/3` adds or takes back; any signed-in, verified reader who
  may view the topic reacts (not to deleted messages, not in locked or archived topics);
  rate-limited (`:react`). Reactions store no notification (steward decision, 2026-10-23:
  the Notifications page is gone; older `"reaction"` rows stay unused); the author gets a
  live bubble. After each change
  `{:reactions, message_id, summary}` goes to the topic, worked out once (NF-01).
  `TopicLive` shows `ReactionComponents.reaction_bar/1` under each message (count when
  several chose an emoji; buttons with `aria-pressed`), a 🙂 `<details>` among the actions
  (`add_reaction/1`: the eight defaults and +) and the + dialog (`emoji_picker/1`, reusing
  the `InlineCard` hook with `data-close-event`). The server renders only its frame: the
  `EmojiPicker` hook (`assets/js/emoji_picker.js`, `phx-update="ignore"`) fetches
  `/emoji-index.json?v=` (`EmojiController`, `Emoji.index_json/0`, built at compile time,
  cached for a year), draws the groups once per page, searches in the browser and pushes
  `"react"`. Never send the emoji list over the live connection (1,881 emoji, 550 KB).
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
- **Page frame and look**: `Layouts.app` draws the header bar (server name, search box,
  Unread, Moderation, and the account menu: a `<details>` holding
  Profile and account, Admin, Theme and Sign out, so it opens without JavaScript), the
  categories sidebar (each category with the topics the user follows there,
  `Reading.list_followed_topics/1`, oldest followed first so the list stays put; past four, a
  "N more topics" `<details>`; each with an unfollow ×, shown on hover, focus or the topic on screen, a
  form to `DELETE /t/{id}/follow` with `return=back`, which `FollowController` sends back to
  the same-host `Referer`; long names end in "…", the lists' grid columns being
  `minmax(0, 1fr)`) and the content column (`width={:narrow}` for reading, `:wide` for the
  home grid and the admin panel; pass `category=` to mark it in the sidebar, and `topic=` on
  a topic page). The topic on screen is highlighted (`.sidebar-topic.is-current`,
  `aria-current`), never folded under "more topics", and listed under its category even
  when not followed, with a "+" (`POST /t/{id}/follow`, `return=back`) where the × would be;
  a new message in a sidebar topic makes its name glow (`.sidebar-burn`, half the composer's
  burn), from a notification or the `"topic_activity"` event `TopicLive` pushes (steward
  decisions, 2026-10-23). The sidebar
  lists `Forum.list_category_summaries/1` (view right, in the query) in the home page's
  order and sections (`Forum.sections/2`; groups fold away as `<details>`); `assets/js/sidebar.js` hides it on wide screens (remembered in `localStorage`, applied
  before paint by `theme.js`) and opens it as a drawer on narrow ones, where a quick sideways
  swipe right opens it and left closes it; followed topics there carry a dot for what is
  new since last opened (`Reading.activity/2` over the unread messages and their
  notifications: grey new, blue a +role mention, orange a reply, red an @mention; the
  strongest wins) and a bolder
  name; and (`swipe/5`: not from the left edge, not in code,
  tables, text boxes or the emoji picker; steward decision, 2026-10-23); All categories, Filter
  by tag, Rules & Roles and Help sit above its categories. The home page shows no title (its `<h1>`
  is `sr-only`: the header names the server) and its sections open with `.section-divider`
  titles (Fraunces, a line across the page). The home page is a
  category grid (topic count, last activity: MVP §5) above `Forum.list_active_topics/2`.
  Styles live in `assets/css/app.css` as named components inside `@layer components`, on the
  daisyUI theme tokens (light and dark). Every category mark comes from
  `TopicComponents.category_mark/1`: a category's icon on a tile of its colour (RP-03; steward
  decision, 2026-10-23: `categories.icon` and `colour` `#rrggbb`, set in **Admin →
  Categories** with an icon picker, a hex field filled by a colour picker, and a preview;
  audited), its initial on its colour, or its initial on one of eight tints from its id
  (`CategoryIcons.tint/1` when only an icon is set). The 63 icons (the steward's, AGPL) live
  in `Idejo.Forum.CategoryIcons`, parsed into shapes at compile time and drawn as SVG elements
  (`TopicComponents.icon_shapes/1`), never raw HTML; shapes take white or near-black,
  whichever contrasts better (`contrast/1`); names via `IdejoWeb.CategoryIconNames`. Colours
  are SVG `fill` attributes or classes, never `style`. Elements that belong to a category
  (cards, topic rows, the message list, sidebar links, the category header) carry
  `cat-{id}`; the root layout's `Layouts.category_colours/1` sets `--cat` for each category
  the reader may view in one `<style>` with the request's nonce (never a `style` attribute;
  AC-05: no other ids), and the "Colour, lines and glow" section of `app.css` draws their
  line and hover glow from it. Inline links in messages have a hue per kind (theme colours),
  a hairline and a hover glow; the dark theme turns `--shadow-soft` / `--shadow-lift` into
  faint glows. Times in lists read "5 min
  ago" (`TopicComponents.time_ago/1`), with the exact time in `datetime` and `title`.
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
  falling back to "Idejo". The Idejo logos (steward decision, 2026-10-23; © Mariano Pictet,
  CC-BY-4.0, in NOTICE and REUSE.toml): the small one (`/images/logo-small.png`, also
  `/favicon.ico` and the `rel="icon"`) before the server name in the header; the full one
  (`Layouts.full_logo/1`, `/images/logo.svg`; `/images/logo.png` as a raster copy) above the
  sign-in, sign-up and setup pages, inverted by the dark theme. Pages set `page_title`; the title reads "Page · Server name". No
  framework branding in the interface.
- Emails built in a context use `IdejoWeb.Gettext` (the one Gettext backend); that is the only
  web module a context may reference.
- **Lock and pin** (TP-14): `Forum.moderate_topic(moderator, topic, :lock | :unlock | :pin |
  :unpin, reason)` needs `:moderate` in the topic's category; locking closes open messages,
  archived topics are never locked or unlocked. Each change is logged (MO-03) with an
  `update` activity, then broadcasts `{:topic_changed, id}` so `TopicLive` rechecks the post
  right. Moderators get a "Moderate this topic" form on the topic page
  (`TopicModerationController`, POST `/t/{id}/moderate`, no JavaScript); topic lists and
  pages show Locked and Pinned badges.
- **Topic title** (steward decision, 2026-10-23): `Forum.rename_topic(user, topic, title,
  reason)` for those `Forum.can_rename_topic?/2` allows: `:moderate` in the category, or the
  starter while they may post (`can_post?/2`); never archived topics. The slug follows the
  title (old slugs 301, TP-06); a moderator renaming someone else's topic is logged as
  `topic.rename` (`from`/`to`); an `update` activity carries `name`; then
  `{:topic_changed, id}`. On the topic page a pencil after the `<h1>` text
  (`#rename-topic-link`, shown on hover or focus, always on touch screens) opens
  `#rename-topic` by `:target` (no JavaScript needed; `assets/js/title_edit.js` only moves
  the focus), a form posting to `/t/{id}/title` (`TopicTitleController`).
- **Archive and delete a topic** (steward decision, 2026-10-23), in "Moderate this topic",
  for `:moderate` in its category: `Forum.archive_topic/3` moves it to the Archive
  (`archive_category/1`, made first, outside the topic's transaction) with `state:
  "archived"`, closes its open messages and drops its category's own tags (`topic.archive`
  logged under the old category); `Forum.delete_topic/3` deletes the row and, by the
  foreign keys' cascades, everything in it (`topic.delete` logged with title and category, a
  `delete` activity, open messages' timers stopped). The delete is its own form with a
  required confirmation box (`confirm=yes`, checked by `TopicModerationController`). Both
  broadcast `{:topic_changed, id}`. A new table that references topics or messages needs an
  `on_delete` that lets this work.
- **Move a topic** (TP-15): `Forum.move_topic(moderator, topic, target, reason)` needs
  `:moderate` in both categories (`Forum.list_move_targets/2`), never into the Archive; open
  messages stay open and links keep working. Logged under the old category with `from`/`to`
  in `details`, plus an `update` activity; `{:topic_changed, id}` makes viewers who may not
  view the new category lose the topic. A "Move to" choice in the topic page's moderator form.
- **Move messages** (TP-15 split and merge; steward decision, 2026-10-23):
  `Forum.move_messages(moderator, topic, ids, {:new, %{"title", "category_id"}} |
  {:existing, topic}, reason)` needs `:moderate` in both categories, never the Archive or an
  archived topic; the source's opening message never moves. Open messages close first
  (`Messages.close_logged_in_transaction/3`, logged); the new topic is opened by the
  earliest moved message's author; in an existing topic messages sort by time (older ones
  come before its opening message). Counts follow, one `messages.move` log entry under the
  source's category, an `update` activity per message, then `{:messages_moved, id}` to both
  topics (viewers reload). Reply links stay across topics; `TopicLive` shows a quote leading
  elsewhere only to readers who may view it (`Forum.viewable_message_ids/2`). In
  `TopicLive`, a message's "Moderate" opens `MessageModerationComponents.moderate_card/1` (a
  dialog: close, delete, "Select to be moved"); selecting shows checkboxes and
  `move_banner/1` ("Move all selected messages to": New thread / Existing thread), and
  `move_dialog/1` takes a title and category or searches `Forum.search_move_targets/3`.
  The card's "Select multiple messages for deletion" (MO-02; steward decision, 2026-10-23)
  uses the same checkboxes (`select_for: :delete`: messages not deleted and not the
  moderator's own) with `delete_banner/1`; `Messages.delete_many_as_moderator/4` deletes them
  in one transaction, each logged.
- **Reports** (MO-01, `Idejo.Moderation`): signed-in users report others' messages they may
  view, with a reason (`/m/{id}/report`, `ReportController`, no JavaScript; one open report
  per reporter and message). `/moderation` (`ModerationController.index`) shows the open
  reports of the categories the viewer moderates (owners and administrators: all), grouped by
  message, oldest first; Resolve or Dismiss closes all of a message's open reports
  (`Moderation.handle_reports/4`), logged as `report.resolve` / `report.dismiss`. The header's
  Moderation link shows how many messages wait (`Moderation.open_report_count/1`).
- **Moderator delete and edit** (MO-02): `Messages.delete_as_moderator/3` sets
  `deleted_at`/`deleted_by_id` (closing an open message first), counts the topic one message
  less and resolves its open reports; the text and versions stay for moderators (steward
  decision). Every reader-facing query must leave deleted messages out (search, notifications,
  unread counts) and every action refuse them (report, fork, edit). `TopicLive` shows readers
  "Message deleted by a moderator", a run of them as one "N messages deleted by a moderator"
  line (the other `<li>`s stay, `hidden`, for permalinks); moderators see the text with a
  badge. `Messages.edit_as_moderator/4` edits others' closed messages like an author's edit
  (versions kept). Each message has a "Moderate" form for moderators (`"moderate_message"`:
  close or delete, with a reason); every action is logged.
- **Bans** (MO-02, `Accounts.ban_user/4`, `unban_user/3`; extra review: DV-06): only server
  moderators (`Access.server_moderator?/1`: owners, administrators, or a role allowing
  `:moderate` server-wide) ban, for 1/7/30/365 days or for good, from the "User actions"
  button of the user card, on `/u/{id}` and in a topic's dialog
  (`UserComponents.card_data/3` gives them `actions`; a `<details>`, no JavaScript needed;
  `BanController`, POST / DELETE `/u/{id}/ban`, back to the topic through a checked
  `return_to`). New moderation actions on an account join that menu. Owners, administrators
  and oneself are never banned. A ban deletes the account's session tokens (and the controller disconnects its
  LiveViews); `Accounts.get_user_by_session_token/1` returns nothing for a banned account and
  sign-in says it is banned only after the right password. `Accounts.banned?/2` ends a ban by
  itself at `banned_until`. Logged as `user.ban` / `user.unban` with no category: server
  moderators see those entries. `Moderation.moderator?/1` counts server moderators.
- **Moderation log** (MO-03, `Idejo.Moderation`): every moderator action calls
  `Moderation.record(moderator, "subject.action", target, reason: …, details: …)` in the same
  transaction as the action; `target` is a message, topic or user, and the entry keeps the
  target's category for visibility. Append-only (database trigger); `target_id` and
  `category_id` are plain ids, not references. `/moderation/log` (`ModerationController`, no
  JavaScript) shows moderators the entries of the categories they moderate, and owners and
  administrators all of them; `Moderation.moderator?/1` gates it and the header link. Add a
  label for each new action in `ModerationHTML.action_label/1`.
- **Rate limits** (SP-05, `Idejo.RateLimit`, Hammer/ETS; extra review: DV-06): per IP in
  plugs (`IdejoWeb.Plugs.RateLimit`: `:request` on every request in the endpoint, `:sign_in`,
  `:sign_up`, `:reset_password` in their controllers; 429 with `Retry-After`), per user in the
  contexts (`:commit`, `:new_message`, `:new_topic`, `:report`, `:upload` →
  `{:error, :rate_limited}`, which every caller must handle). Limits are in
  `Idejo.RateLimit`. `IdejoWeb.Plugs.ClientIp` takes the visitor's address from the rightmost
  `X-Forwarded-For` only when the peer is on a private network (Caddy); `:behind_proxy` turns
  it off. Off in tests (`config :idejo, :rate_limits, enabled: false`); `rate_limit_test.exs`
  turns them on (not async) and uses addresses and accounts of its own.
- **Command-line recovery** (AD-09, `Idejo.Release`; extra review: DV-06):
  `rel/overlays/bin/idejo-admin` (`reset-owner-password [USERNAME]`, `backup`,
  `restore FILE [--yes]`, `health`) runs
  `Idejo.Release` functions with `bin/idejo rpc` when the server is running, else
  `bin/idejo eval` (which starts only the repo, through `Ecto.Migrator.with_repo`). They print
  on standard output (under rpc standard error goes to the server's log) and fail with
  `exit({:shutdown, 1})`, never `System.halt/1`, which under rpc would stop the server. The
  owner reset prints a random password, ends every session (disconnecting LiveViews when the
  endpoint runs: the one web call `Release` makes) and is audited as `user.password_reset`
  with no admin. `restore` runs only with the server stopped (eval), after a typed
  confirmation. Usage: `docs/deploying.md`.
- **Backups** (AD-05, `Idejo.Backup`): one tar per backup in `:backup_dir`
  (`IDEJO_BACKUP_DIR`, the `/data/backups` volume; `tmp/test_backups` in tests),
  `idejo-YYYYMMDD-HHMMSS.tar` (UTC) holding `manifest.json` (format, last migration),
  `database.dump` (`pg_dump -Fc`, taken before the uploads so every file it names is there)
  and `uploads/<name>`; written as `.tmp` and renamed. `Idejo.Backup.Worker` runs at 03:00 UTC
  (Oban cron, queue `maintenance`) and keeps the newest 7 (steward decision; v1's NF-07
  says 14). `restore/1` refuses archives with other names or from a newer schema, backs up
  first, drops and recreates schema `public`, `pg_restore`s, migrates, replaces the uploads
  and audits `backup.restore`. `pg_dump`/`pg_restore` must match the server's major
  version: the Dockerfile installs `postgresql-client-${PG_MAJOR}` from the PostgreSQL apt
  repository (change it with the `db` image), `IDEJO_PG_BIN_DIR` points elsewhere. Tests
  needing them are tagged `pg_tools` (skipped with a note when missing, never on CI); the
  restore test uses a database of its own through a dynamic repo, outside the sandbox.
- **Background jobs**: Oban (`config :idejo, Oban`, `oban_jobs` migration pinned to
  version 14; queues `maintenance` and `messages`), `testing: :manual` in tests (use
  `Oban.Testing`).
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
mix test --only flow:live-conversation           # the M3 exit flow (with --only req:NF-02)
mix format --check-formatted
mix credo --strict
mix dialyzer
mix sobelow --config
mix deps.audit && mix hex.audit
reuse lint                         # SPDX headers (pip install reuse)
mix precommit                      # everything above that CI runs, Dialyzer too, but not reuse lint
load/run.sh [--hot --writers 10]   # load test before a release (NF-01, NF-04; docs/load-testing.md)
```

Production bundle: `deploy/` (see `deploy/docker-compose.yml`). Server setup step by step:
`docs/deploying.md`. For the people who use it: `docs/admin-guide.md` (admin panel,
permissions, moderation) and `docs/member-guide.md` (one page: the keys and the composer).
They quote the interface's labels: a change to a label, a setting or a workflow updates them
in the same pull request (DV-01).

## Milestones (MVP §7)

- [x] M0 — Foundations — repo, headers, NOTICE, CLA check, CI, Compose with HTTPS
- [x] M1 — Accounts and structure — roles, categories, permission grid, invites, profile, admin pages, audit log; exit test "admin sets up the server"
- [x] M2 — Topics
- [x] M3 — Growing messages
- [x] M4 — Around the conversation
- [ ] **M5 — Moderation and operations**

Current milestone: **M5**. Do not start work belonging to a later milestone.

M4 exit check (MVP §7): search finds a message by a word added in its last commit
(`test/idejo/search_test.exs`, SE-03); a growing message produces one notification
(`test/idejo/notifications_test.exs`, NO-02).
Not implemented in M4, left for later:
- live delivery of the notification count (moot since the bell was removed, 2026-10-23).

M3 exit check (MVP §7): all GM tests pass; the "live conversation" flow passes as an
end-to-end test (`test/idejo_web/flows/live_conversation_test.exs`, steps 1-4; steward
decision); a server restart mid-message loses nothing
(`test/idejo_web/live/restart_mid_message_test.exs`, NF-02: restarts the engine's processes,
not async).
Not implemented in M3, left for M4:
- step 5 of the flow, "New topic from this" (TP-09): added to the flow test with TP-09;
- GM-13 for notifications, unread counts and search; its test covers the message count now.

M2 exit check (MVP §7): the "member starts a topic" flow passes as an end-to-end test; a public
topic renders without JavaScript.
Not implemented in M2, left for later milestones:
- live delivery (TP-04), in M3;
- unread tracking (TP-07), along with TP-03's unread marker, in M4.

