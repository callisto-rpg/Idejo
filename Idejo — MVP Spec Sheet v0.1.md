# Idejo — MVP Spec Sheet v0.1

Oct 17, 2026 · @Mariano

## 1. Goal

v0.1 proves the core idea with one real pilot community: admin-made categories, member-made topics, and conversations made of growing messages that stay readable and findable like a forum. Everything not needed to test that is deferred to v1.

Requirement IDs match the *Idejo — Spec Sheet v1*; this document only states how each kept requirement is cut down for v0.1. All rules not mentioned here follow v1.

**Success criteria**

- A pilot community runs on one minimum-size server (2 vCPU, 2 GB RAM) for four weeks without data loss.
- Every growing-message rule (GM-01 to GM-14, GM-16) has passing automated tests.
- Pilot members can use the growing-message keys without being taught, and say topics read better than in their usual chat tool (short survey at the end of the pilot).
- Public topics are readable without an account and appear in a search engine within the pilot period.
- A non-technical admin installs, configures categories and roles, and restores a backup by following the docs alone.

## 2. Scope at a glance

v0.1 keeps the complete growing-message behaviour and a minimal version of everything around it.

| Area | In v0.1 | Waits for v1 |
| --- | --- | --- |
| Structure | One level of categories; public, members-only or role-restricted | Sub-categories, landing page, category templates |
| Topics | Create, live conversation, inline replies, fork to new topic, @user mentions, images, lock, pin, move | Role/@here mentions, file attachments, link previews, reactions, solutions, tags, polls, merge and split, presence |
| Growing messages | All rules, 45 s server-wide window | Per-category window or switch-off (GM-15) |
| Roles and permissions | Built-in roles, custom roles, per-category allow/deny per role for four rights | Per-user overrides, “view as”, delegated management, automatic and timed roles |
| Accounts | Email sign-up (open or invite-only), password reset, guest reading, self-deletion | Two-factor, passkeys, SSO, data export, trust levels, profile fields |
| Moderation | Reports, delete, edit, lock, close open message, ban, action log | Automod, approval queue, raid protection, appeals |
| Search and SEO | Full-text search with category filter; server-rendered public pages; sitemap | Feeds, topic lists, external search engines, duplicate suggestions |
| Notifications | In-app mentions and replies | Email, digests, push, quiet hours |
| Accessibility | Keyboard use, screen-reader handling of growing messages, no-JS reading | Themes, translations (strings already extractable), RTL |
| Administration | Install, settings, users, roles, categories, nightly backup, CLI recovery | Auto-archive, importers, branding, metrics, S3 storage |
| API and federation | Internal API used by the web app; stable URIs and activity log from day one | Public API tokens, webhooks, bots, plugins, federation |
| Licensing and process | AGPL-3.0-only headers, NOTICE, source link, CLA check, AI-commit trailers, CLAUDE.md, tests per ID | Trademark policy, commercial licence |

## 3. Requirements

Every row is required for v0.1. “As v1” means the v1 requirement applies unchanged.

| ID | v0.1 form |
| --- | --- |
| GM-01 to GM-14 | As v1: open, append in the same composer on the same line, 45 s window not reset by appends that only limits when a new message can start, Ctrl+Enter new line or new message, Shift+Enter line break, no size limit, pencil icon and countdown, composer in place with replies below it, one open message per topic, sent text in higher contrast and edited in place with “view earlier version”, close on lock or disconnect, first message never live |
| GM-15 | Window length set server-wide only (default 45 s) |
| GM-16 | As v1: moderators can close an open message |
| TP-01, TP-02 | As v1: title, first message (tags come later) |
| TP-03 | Topic list with title, starter, message count, last activity, unread marker; pinned first |
| TP-04 to TP-07 | As v1: live delivery with catch-up, full history, permalinks, unread tracking |
| TP-08, TP-09 | As v1: inline replies; fork any message into a new topic |
| TP-10 | @user mentions only |
| TP-11 | Markdown with code blocks and preview |
| TP-12 | Images only, one server-wide size limit, stored on local disk |
| TP-13 | Follow a topic |
| TP-14 | Open and locked states; pin within a category |
| TP-15 | Move a topic to another category |
| RP-01, RP-02 | As v1: built-in roles; custom roles with name, colour and order |
| RP-03 | Create, rename, reorder and delete categories (one level) |
| RP-04, RP-05 | Per category, allow or deny per role for four rights: view, start topics, post, moderate |
| RP-06 | Several roles per user; deny wins; highest role sets colour |
| AC-01, AC-02 | Email sign-up with verification; open or invite-only; password reset by email |
| AC-04 | Display name and avatar |
| AC-05, AC-07 | As v1: guest reading; users delete their own account |
| MO-01 | Report a message with a reason |
| MO-02 | Delete, edit, lock, close open message, ban account |
| MO-03 | Action log with moderator, target, reason, time |
| MO-06 | As v1: moderators see version history |
| SE-01 to SE-03 | Full-text search with category filter, permission-aware, one document per message |
| SE-04 | Server-rendered public pages with clean URLs, sitemap and canonical links |
| NO-01, NO-02 | In-app notifications for mentions and replies; one per growing message |
| AX-01 to AX-04 | As v1; all interface strings in one extractable file (English only) |
| AD-01 | Docker Compose install with first-run wizard |
| AD-02 | Admin pages: settings, users, roles, categories |
| AD-04 | Server-wide window setting |
| AD-05 | Nightly database and upload backup to local disk; restore by command |
| AD-08, AD-09 | As v1: SMTP settings with test; command-line recovery |
| SP-01, SP-02, SP-04, SP-05, SP-06 | As v1 (TLS, password hashing and sessions, no third-party scripts, web hardening, admin audit log) |
| FD-01 to FD-03 | As v1: stable URIs, activity outbox, Markdown plus HTML storage — cheap now, costly to add later |
| CL-01, CL-02 | Responsive web app; no-JS read view |
| NF-01 to NF-04 | As v1 |
| LI-01 to LI-03, LI-05, LI-08 | As v1 |
| DV-01 to DV-06 | As v1 |

## 4. Key user flows

Three flows cover everything the pilot must do; each becomes an end-to-end test.

**Admin sets up the server**

1. Runs the install command; opens the address; the wizard asks for server name, owner account and SMTP settings.
2. Creates categories (e.g. Announcements, General, Help) and sets their order.
3. Creates custom roles (e.g. Team, Members) and, per category, allows or denies view, start topics, post and moderate.
4. Switches registration to invite-only and sends invite links to the pilot members.

**Member starts a topic**

1. Opens a category and selects “New topic”.
2. Writes a title and a first message; nobody sees it yet.
3. Posts: the topic appears at the top of the category list with its first message closed.

**Live conversation**

1. A member opens the topic and presses Enter after a first line: the message appears for everyone with a pencil icon; the author sees 45 s counting down. The sent text stays in the composer, in higher contrast.
2. They keep typing and pressing Enter; each part joins the same message on the same line. Ctrl+Enter continues on a new line of the same message. Another member replies meanwhile; the reply appears below the author’s composer, which moves up and keeps growing.
3. The author fixes a typo in an earlier line, right in the composer; the changed text shows as unsent until Enter, then a discreet “view earlier version” tag appears.
4. The countdown ends: the author is still typing in the same message and Enter still adds to it. Only now does Ctrl+Enter close it (the pencil disappears) and start a new message on a new line.
5. A side question comes up: someone selects that message and chooses “New topic from this”; the new topic links back to it.

## 5. Screens

Ten screens make up v0.1; public ones are server-rendered and work without JavaScript.

| Screen | Contents | Public |
| --- | --- | --- |
| Home | Server name, category list with description, topic count and last activity | Yes |
| Category | Topic list (pinned first), “New topic” button | Yes |
| Topic | Title, messages with replies, pencil icons, “view earlier version” tags; composer in place of the author’s open message, with countdown and “new line” button | Yes (read only) |
| New topic | Title, first-message editor with preview | No |
| Search | Query box, category filter, results with excerpts | Yes |
| Notifications | Mentions and replies, unread first | No |
| Sign-up, sign-in, password reset | Forms; invite code field when invite-only | Yes |
| Profile and account | Display name, avatar, password change, delete account | No |
| Moderation | Report queue and action log | No |
| Admin | Settings (incl. window length, registration mode, SMTP), users and bans, roles, categories and permission grid | No |

## 6. Data model

PostgreSQL tables for v0.1. A growing message is stored as a row in `messages` plus one row per Enter in `commits`; the end of the window is fixed at the first commit (`closes_at = opened_at + window`) and marks when the author may start a new message, not when the message closes, so a restart simply reloads open messages.

| Table | Key fields | Notes |
| --- | --- | --- |
| users | id, uri, email, password\_hash, display\_name, avatar\_id, status, origin, created\_at | `origin` always “local” in v0.1 (FD-05 ready) |
| roles | id, name, colour, position, built\_in |  |
| user\_roles | user\_id, role\_id |  |
| categories | id, uri, slug, name, description, position, visibility | One level only; `parent_id` column added but unused |
| category\_permissions | category\_id, role\_id, right, effect | right: view, start, post, moderate; effect: allow, deny |
| topics | id, uri, category\_id, author\_id, title, slug, state, pinned, forked\_from\_message\_id, message\_count, last\_activity\_at |  |
| messages | id, uri, topic\_id, author\_id, reply\_to\_id, state, opened\_at, closes\_at, closed\_at, body\_md, body\_html, edited, search\_vector | Ordered by `opened_at` (GM-08) |
| commits | id, message\_id, position, text, created\_at | The change sent at that Enter (added, edited or deleted text). Written before it is acknowledged (NF-02) |
| message\_versions | id, message\_id, body\_md, created\_at | Snapshot saved when an earlier commit is edited (GM-11) |
| read\_positions | user\_id, topic\_id, last\_read\_message\_id |  |
| follows | user\_id, topic\_id |  |
| notifications | id, user\_id, kind, message\_id, read\_at | One per growing message (NO-02) |
| reports | id, message\_id, reporter\_id, reason, status |  |
| mod\_actions | id, moderator\_id, action, target\_type, target\_id, reason, created\_at | MO-03 |
| audit\_log | id, admin\_id, change, before, after, created\_at | SP-06 |
| activities | id, actor\_uri, verb, object\_uri, target\_uri, payload, created\_at | Outbox for future federation (FD-02) |
| invites | code, created\_by, used\_by, expires\_at |  |
| uploads | id, user\_id, path, mime, size, created\_at | Images only |
| settings | key, value | e.g. `gm_window_seconds = 45`, registration mode, SMTP |

## 7. Build plan

Six milestones, in order; each ends with its exit check passing in CI before the next starts. Growing messages come after static topics so the core feature is built on a working base.

1. **M0 — Foundations:** repository with CLAUDE.md, licence headers, NOTICE, CLA check, CI (formatter, linter, tests), Docker Compose with Phoenix, PostgreSQL and Caddy.
   - Exit: an empty app deploys with HTTPS from one command; CI is green.
2. **M1 — Accounts and structure:** sign-up with invites, sign-in, password reset, roles, categories, permission grid, admin pages, audit log.
   - Exit: the “admin sets up the server” flow passes as an automated test.
3. **M2 — Topics:** new topic, topic list, closed messages, inline replies, permalinks, public no-JS pages, sitemap.
   - Exit: the “member starts a topic” flow passes; a public topic renders without JavaScript.
4. **M3 — Growing messages:** live delivery and catch-up, open/append in the same composer, window timers, keys, composer in place, pencil icon and countdown, edits with earlier versions, early close, screen-reader announcements.
   - Exit: all GM tests pass; the “live conversation” flow passes; a server restart mid-message loses nothing.
5. **M4 — Around the conversation:** @mentions, in-app notifications, unread tracking, follow, fork to new topic, image uploads, search.
   - Exit: search finds a message by a word added in its last commit; a growing message produces one notification.
6. **M5 — Moderation and operations:** reports, moderator actions and log, bans, nightly backup and restore, command-line recovery, accessibility audit, load test.
   - Exit: every item in section 8 is ticked; pilot starts.

## 8. Definition of done

v0.1 is ready for the pilot when every box below is ticked.

- [ ] Every requirement in section 3 has a test named after its ID, and all tests pass in CI.
- [ ] The three flows in section 4 pass as end-to-end tests.
- [ ] A fresh install on a 2 vCPU / 2 GB server works from one command with automatic HTTPS.
- [ ] Load test: about 200 people online, live delivery within 200 ms (NF-01, NF-04).
- [ ] Restart test: no committed text lost; open messages keep their original window end.
- [ ] Backup restored on a second machine by following the docs.
- [ ] Accessibility check of the topic page with keyboard and a screen reader.
- [ ] Public topic readable with JavaScript off; sitemap reachable.
- [ ] AGPL source link, NOTICE attribution and CLA check in place.
- [ ] Admin guide and a one-page member guide (keys and the pencil icon) written.
