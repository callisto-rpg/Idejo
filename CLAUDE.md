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
sent first keeps the old text in `message_versions` (GM-11). History is kept only for edits
(TP-05): a message that only received appends keeps just its final text, with no versions and
no per-commit rows. Events go to `"topic:{id}"` on `Idejo.PubSub`: `{:message, message}` and
`{:window_ended, id}`. The window length is the
`gm_window_seconds` setting (default 45, 10–600 s), set in **Admin → Settings** (GM-15, AD-04;
server-wide only in v0.1, no per-category override); a change applies to messages opened after
it. Tests set `recover_open_messages: false` and call
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
  decorative). The same page changes the password (AC-01, below).
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
  A reply's `reply_to_id` must be a message of the same topic, set when the reply opens;
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
  when nothing is open). Only a text box whose placeholder names the keys: no countdown,
  button or status. The `Composer` hook (`assets/js/composer.js`) pushes `"commit"`
  (`body`, `break`) and keeps the text; its `finishSentence/1` must match the server's dot
  rule. `data-sent` and the `"composer_sent"` push restore the open message after a reload
  or reconnect. No Ctrl+Enter on touch screens for now (steward decision).
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
- **Unread** (TP-07, `Idejo.Reading`): one `read_positions` row per user and topic, holding
  the last message seen. Opening a topic (`TopicController`, and `TopicLive` on connect)
  marks it read with `Reading.mark_read/2`, and so does every new message arriving while it
  is open (steward decision); appends do not move it. Unread = messages by others opened
  after that message (`opened_at`), so a growing message counts once and never turns unread
  again as it grows (GM-13). Without a position, everything before the user's sign-up is
  read. `/unread` (`UnreadController`, signed in, linked from the header) lists topics with
  unread messages across viewable categories (`Reading.list_unread_topics/2`).
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
  row per user and message (`kind`: mention, reply, follow). A new message notifies the users
  it mentions, the author it replies to and the topic's followers, in that priority, never
  its author or anyone who may not view the topic (`notify_new/2`); an append or an edit
  notifies only someone newly mentioned, turning their earlier notification for that message
  into an unread mention (`notify_mentions/2`). Both run inside the transaction that writes
  the message; any new way of writing a message must call them. `/notifications`
  (`NotificationController`, no JavaScript) lists them unread first; `/notifications/{id}`
  marks one read and redirects to `/m/{id}`. The header link shows the unread count, counted
  per page render (not live). Notifications for topics the user can no longer view are hidden.
- **@mentions** (TP-10, @user only, no autocomplete: steward decision): every body renders
  through `Idejo.Messages.Body.to_html/1` (messages, previews, versions), never
  `Idejo.Markdown.to_html/1` directly. `Markdown.mentions/1` finds `@username` outside code and
  links; each one naming an active user (case-insensitive) is stored as a link to `/u/{id}`
  (styled by `a[href^="/u/"]`: the sanitiser keeps no classes). `Body.mentioned_users/1` is
  for notifications. `/u/{id}` (`UserController`, public) shows the user card
  (`UserComponents.user_card/1`: initial until avatars, display name, username, roles); in a
  topic the `Mentions` hook opens it in a `<dialog>` (`UserCard` hook, `"show_user"` /
  `"hide_user"`) instead (steward decision). Add the full-profile link when profiles exist.
- **New topic from this** (TP-09): every message has a "New topic from this" link for users
  who may start a topic somewhere (`Forum.list_startable_categories/1`). It opens
  `NewTopicLive` at `/m/{id}/new-topic` (`:fork`): the source's excerpt and a category choice.
  `Forum.create_topic/4` with `forked_from: message` sets `topics.forked_from_message_id`
  (needs view of the source and `:start` in the target), adds `forkedFrom` to the activity and
  broadcasts `{:forked, message_id}` to the source topic. The new topic's page shows
  "Continued from …"; the source message shows "Continued in …" (`Forum.list_forks/2`). Both
  only when the viewer may view the other topic.
- **Follow** (TP-13, `Idejo.Reading`): `follows` rows (user, topic, `following`). Starting a
  topic or posting in it follows it (`Reading.auto_follow/2` inside the transaction that
  writes the message); an explicit unfollow stays as `following: false`, so posting again does
  not undo it (steward decision: followers get notified of new messages, with NO-01). The
  topic page has Follow / Unfollow forms posting to `/t/{id}/follow` (`FollowController`,
  POST / DELETE, no JavaScript needed).
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
- **Page frame and look**: `Layouts.app` draws the header bar (server name, search box,
  Unread, Moderation, the notifications bell, and the account menu: a `<details>` holding
  Profile and account, Admin, Theme and Sign out, so it opens without JavaScript), the
  categories sidebar (each category with the topics the user follows there,
  `Reading.list_followed_topics/1`, oldest followed first so the list stays put; past four, a
  "N more topics" `<details>`; each with an unfollow × shown on hover or focus, a form to
  `DELETE /t/{id}/follow` with `return=back`, which `FollowController` sends back to the
  same-host `Referer`) and the content column (`width={:narrow}` for reading, `:wide` for the
  home grid and the admin panel; pass `category=` to mark it in the sidebar). The sidebar
  lists `Forum.list_category_summaries/1` (view right, in the query) most recently active
  first; `assets/js/sidebar.js` hides it on wide screens (remembered in `localStorage`, applied
  before paint by `theme.js`) and opens it as a drawer on narrow ones. The home page is a
  category grid (topic count, last activity: MVP §5) above `Forum.list_active_topics/2`.
  Styles live in `assets/css/app.css` as named components inside `@layer components`, on the
  daisyUI theme tokens (light and dark); categories get one of eight tints from their id
  (`TopicComponents.category_mark/1`, classes, never `style`). Times in lists read "5 min
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
  falling back to "Idejo". Pages set `page_title`; the title reads "Page · Server name". No
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
- **Move a topic** (TP-15): `Forum.move_topic(moderator, topic, target, reason)` needs
  `:moderate` in both categories (`Forum.list_move_targets/2`), never into the Archive; open
  messages stay open and links keep working. Logged under the old category with `from`/`to`
  in `details`, plus an `update` activity; `{:topic_changed, id}` makes viewers who may not
  view the new category lose the topic. A "Move to" choice in the topic page's moderator form.
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
  version 14), `testing: :manual` in tests (use `Oban.Testing`).
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
- live delivery of the notification count (it is counted per page render);
- removing uploads that no message or avatar uses (images inserted, then deleted before
  sending).

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

