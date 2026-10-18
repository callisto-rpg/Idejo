# Idejo — Spec Sheet v1

Oct 17, 2026 · @Mariano

## 1. Overview

Idejo version 1 is a self-hosted, open-source community server: one install hosts one community, organised like a phpBB forum, where every topic is a live chat. Administrators define categories and custom roles; members start topics; quick lines merge into “growing messages” so conversations read like a forum while feeling like a chat.

- **Operator:** anyone running their own server (association, project, club, company).
- **Readers:** members and, for public categories, anonymous visitors and search engines.
- **Basis:** this spec builds on the *Community Platform — Feature List* and the decisions in section 2.

Priority in requirement tables: **Must** = required for v1 release · **Should** = planned for v1, may slip to v1.x · **Could** = after v1. Requirement IDs (e.g. GM-03) are stable and used for tracking and tests.

## 2. Decisions

The twelve open questions from the feature list are settled as follows; each decision is reflected in the requirements below.

| Question | Decision |
| --- | --- |
| Growing-message countdown | The countdown only sets how soon the author may start a new message; it never ends the message they are typing. Appends do not restart it. No size limit on a growing message. Default window 45 s, adjustable server-wide and per category. |
| Editing an open message | Allowed, in the same composer: sent text stays in it, shown in higher contrast than unsent text. If text already sent is changed (not just added to), a discreet “view earlier version” tag appears. |
| Line break key | Shift+Enter inserts a line break; Enter sends what changed and keeps typing on the same line; Ctrl+Enter sends and continues on a new line, or starts a new message once the window has ended. |
| When a topic stops being live | Optional auto-archive after 65 days of inactivity by default; period editable in server-wide settings. |
| First message of a topic | Same editor as any message. Only differences: it has a title, it takes tags, and it is not live while being typed. |
| Replies inside a topic | Inline replies only. Anyone permitted can select any message, including someone else’s, and create a new topic from it. |
| Communities per install | One community per server. |
| Licence | AGPL-3.0-only with a section 7(b) attribution notice. Copyright steward: Mariano Pictet until an organisation is formed, then transferred to it. Dual licensing kept possible. |
| Voice and video | Not in the product. |
| Federation | Not in v1; the architecture must allow it later. |
| Direct messages and encryption | No direct messages. Traffic is encrypted between client and server (TLS), not end-to-end. |
| Tech stack | Confirmed (section 18), provided the whole system can be built and maintained with Claude Code. |
| Product name and web address | Idejo, at idejo.org. |
| Server sizing | NF-04 and NF-05 accepted as targets. |
| Contributions and AI-generated code | Licence-grant CLA based on Apache templates; every change reviewed by a person, AI-assisted commits marked; lawyer review before any commercial licence (LI-05, LI-08). |

## 3. Scope

Version 1 delivers text conversations in an admin-defined category structure, with roles, moderation, search and a public web presence.

**In version 1**

- Categories and sub-categories, topics, growing messages, inline replies, topic forking
- Custom roles and per-category permissions, managed by administrators
- Accounts, moderation, search, notifications (in-app, email, push)
- Public, search-engine-readable pages; RSS/Atom feeds
- Web admin panel, backups, upgrades, phpBB import
- Public API with real-time events; webhooks

**Out of scope**

- Direct or private messages between users
- Voice, video, screen sharing and stage events
- Several communities on one install
- End-to-end encryption
- Federation and bridges (architecture prepared, see section 15)
- Side threads inside topics

## 4. Information architecture

Four levels, each with a stable URL: server → category (nestable) → topic → message. Permissions are set on categories and flow down.

| Entity | Created by | Key properties | URL pattern |
| --- | --- | --- | --- |
| Server | Installer | Name, branding, rules, registration mode, global settings | `/` |
| Category | Administrators (or delegated roles) | Name, description, order, parent category, visibility, permissions per role, growing-message window, auto-archive setting | `/c/{slug}` |
| Topic | Members with “start topics” right | Title, tags, state (open, locked, archived, solved), pinned flag, category | `/c/{slug}/t/{id}-{slug}` |
| Message | Members with “post” right | Author, body (Markdown), state (open or closed), commits, reply-to reference, reactions, attachments | `/c/{slug}/t/{id}-{slug}#m{id}` |
| Commit | System, at each Enter or Ctrl+Enter | Change to the message text (added, edited or deleted), timestamp, edited flag — the unit a growing message is built from | (internal) |

## 5. Growing messages

The composer *is* the author’s open message. Pressing Enter sends what has changed, but the text stays in the composer and the author keeps typing in the same message, on the same line. Sent text is shown in higher contrast than unsent text, so it is always clear which part is still private.

The composer sits in the topic at the place of the author’s open message. Replies from other members appear below it, so the composer moves up as the conversation continues; with no open message, it sits at the end of the topic.

A fixed window (45 s by default) starts at the first commit. It does not end the message: it only sets how soon the author may start a new one. After the window the author is still typing in the same message until they choose to start a new one. The window is not extended by appends, and a message has no size limit.

&#91;embedded content: message states · compose, open, closed\]

| Key | Action |
| --- | --- |
| Enter | Sends what changed: starts a new message, or commits to the author’s open message. Typing continues in the same message, on the same line |
| Shift+Enter | Line break inside the unsent text, nothing sent |
| Ctrl+Enter (Cmd+Enter on macOS) | Sends what changed and continues on a new line. Within the window the new line stays in the same message; after the window it starts a new message |
| Touch screens | Send button = Enter; a “new line” button beside it = Ctrl+Enter |

| ID | Requirement | Priority |
| --- | --- | --- |
| GM-01 | Enter with no open message posts a new message, open and visible to readers at once | Must |
| GM-02 | Enter while the author has an open message in the topic sends the unsent changes as a new commit; readers see them appear in place. The text stays in the composer and typing continues on the same line, with no line break added | Must |
| GM-03 | The window starts at the first commit; appends never restart or extend it. The window only limits when a new message can be started; it never closes the message or moves the author out of it | Must |
| GM-04 | When the window ends the message stays open and the author keeps typing in it; Enter still commits to it. Only Ctrl+Enter (GM-05) starts a new message | Must |
| GM-05 | Ctrl+Enter sends the unsent changes as a commit and continues on a new line. Within the window that line belongs to the same message; after the window the message closes and the new line starts a new message | Must |
| GM-06 | No size limit on a message; bodies longer than one screen render collapsed with a “show all” control | Must |
| GM-07 | An open message shows a discreet pencil icon to all readers; the author also sees the time left until a new message can be started | Must |
| GM-08 | Messages are ordered by their first commit; replies by others appear below an open message, which keeps its place and keeps growing. The author’s composer is that open message, in place: new replies appear below it and push it up | Must |
| GM-09 | An author has at most one open message per topic | Must |
| GM-10 | The author can edit any commit, while open or after closing. While open, sent text is edited directly in the composer: sent text shows in higher contrast than unsent text; text typed inside or changed within sent text shows as unsent until the next Enter; deleting sent text is sent with the next commit. Adding text at the end is not an edit | Must |
| GM-11 | Changing text of an earlier commit marks the message as edited and shows a discreet “view earlier version” tag; it opens every previous version with its time | Must |
| GM-12 | An open message also closes when its topic is locked or archived, or when the author’s session disconnects | Must |
| GM-13 | Notifications, unread counts, search, feeds and webhooks treat a growing message as one item (see sections 10, 11, 15) | Must |
| GM-14 | The first message of a topic is never live: it is composed privately and posted closed (see TP-02) | Must |
| GM-15 | Window length set server-wide (default 45 s) with a per-category override; consolidation can be switched off per category | Must |
| GM-16 | Moderators can close another user’s open message | Should |

## 6. Topics

A topic is created like a forum thread and then runs as a live conversation of growing messages, with inline replies only.

| ID | Requirement | Priority |
| --- | --- | --- |
| TP-01 | Members with the “start topics” right create a topic in a category with a title (required), tags and a first message | Must |
| TP-02 | The first message uses the same editor as any message; nobody sees it while it is typed; it is posted closed together with the title and tags | Must |
| TP-03 | Category view lists topics with title, starter, tags, message count, participants, last activity and unread marker; pinned topics on top | Must |
| TP-04 | New messages and appends reach every viewer live, with automatic reconnect and catch-up of missed events | Must |
| TP-05 | Full history kept; jump to the first message, the first unread or a date | Must |
| TP-06 | Stable permalink to every topic and every message | Must |
| TP-07 | Per-user read position per topic; “new since last visit” across categories; a growing message counts as one unread item | Must |
| TP-08 | Inline replies: a reply references one message and shows a short excerpt linking to it. No side threads | Must |
| TP-09 | Fork to new topic: a member with “start topics” in the target category selects any message, theirs or someone else’s, and starts a new topic from it; the new topic shows a linked excerpt, and the source message gets a discreet “continued in …” link | Must |
| TP-10 | Mentions: @user, @role, @here (people in the topic now), @everyone; role and everyone mentions gated by permission | Must |
| TP-11 | Composer: Markdown, code blocks with highlighting, spoilers, emoji picker, preview | Must |
| TP-12 | Attachments and inline images with size and type limits per role; link previews fetched by the server | Must |
| TP-13 | Follow topics or whole categories; bookmark single messages | Must |
| TP-14 | Topic states open, locked, archived and solved; pin to the category or the whole server | Must |
| TP-15 | Moderator tools: rename, move to another category, merge topics, split selected messages into a new topic | Must |
| TP-16 | Presence: who is reading the topic right now | Should |
| TP-17 | Reactions on messages; custom server emoji uploaded by admins | Should |
| TP-18 | Mark the message that answered the topic as the solution, in Q&A categories | Should |
| TP-19 | Tags and prefixes; required tags per category | Should |
| TP-20 | Unsent composer text saved server-side and restored on any device | Should |
| TP-21 | Polls inside a topic | Could |

## 7. Roles, categories and permissions

Administrators manage custom roles (as in Discord) and categories (as in phpBB) from the admin panel; permissions are a matrix of roles × rights per category.

| ID | Requirement | Priority |
| --- | --- | --- |
| RP-01 | Built-in roles always present: owner, administrator, moderator, member, guest | Must |
| RP-02 | Role editor: create, rename, colour, icon, rank order and delete an unlimited number of custom roles | Must |
| RP-03 | Category manager: create, nest, reorder by drag and drop, describe and delete categories; deleting asks whether to move or archive their topics | Must |
| RP-04 | Permission matrix per category: view, read history, start topics, post, attach, react, mention roles, mention everyone, fork topics, pin, moderate | Must |
| RP-05 | Sub-categories inherit their parent’s permissions; overrides set allow, deny or inherit per role or per user | Must |
| RP-06 | Users hold several roles; their rights combine, an explicit deny on a category wins, the highest-ranked role sets the name colour | Must |
| RP-07 | Moderator rights can be scoped to one category and its sub-categories | Must |
| RP-08 | “View as”: an admin sees the server exactly as a chosen role or user sees it | Should |
| RP-09 | “Manage roles” and “Manage categories” can be delegated; a delegate cannot grant rights or ranks above their own | Should |
| RP-10 | Self-assigned roles chosen by members from an admin-defined menu | Should |
| RP-11 | Automatic roles granted by trust level, account age or verification | Should |
| RP-12 | Roles that expire on a set date | Could |

## 8. Accounts and profiles

One account per person on the server; anonymous visitors can read public categories. There are no private messages between users.

| ID | Requirement | Priority |
| --- | --- | --- |
| AC-01 | Sign-up with email and password, email verification | Must |
| AC-02 | Registration modes: open, admin approval, invite-only, closed | Must |
| AC-03 | Two-factor sign-in with authenticator codes and passkeys; recovery codes | Must |
| AC-04 | Profile: display name, avatar, bio, pronouns, links, plus fields defined by admins | Must |
| AC-05 | Visitors without an account read public categories and topics | Must |
| AC-06 | Ignore a user: their messages are collapsed for you | Must |
| AC-07 | Users export their data and delete their account themselves | Must |
| AC-08 | List and revoke active sessions and devices | Must |
| AC-09 | Single sign-on via OpenID Connect, SAML or LDAP | Should |
| AC-10 | Trust levels unlocked by account age and activity, used against spam | Should |
| AC-11 | Status: online, away, invisible | Should |
| AC-12 | Profile badges | Could |

## 9. Moderation

Moderators work from one queue, every action is logged, and filters apply to each commit of a growing message as it arrives.

| ID | Requirement | Priority |
| --- | --- | --- |
| MO-01 | Report a message, topic or user with a reason; reports go to the moderation queue | Must |
| MO-02 | Actions: hide, delete, edit, move, lock, close an open message; warn, time out, ban (temporary or permanent; by account, email or IP) | Must |
| MO-03 | Searchable moderation log of every action, with moderator, target, reason and time | Must |
| MO-04 | Approval queue for new topics and messages from new users or in chosen categories | Must |
| MO-05 | Sign-up spam defence: captcha or proof-of-work, disposable-email blocklist, rate limits | Must |
| MO-06 | Moderators see the full version history of any edited message | Must |
| MO-07 | Automod rules: word, link and pattern filters checked on every commit, flood limits, an action per rule | Should |
| MO-08 | Raid protection: join-rate limit and one-click lockdown | Should |
| MO-09 | Private moderator notes on a user | Should |
| MO-10 | One appeal per ban, reviewed in the queue | Could |

## 10. Search, discovery and SEO

Public knowledge must be findable both inside the server and from search engines, which is what a chat-only tool cannot offer.

| ID | Requirement | Priority |
| --- | --- | --- |
| SE-01 | Full-text search over topic titles and messages, filtered by author, date, category, tag and has-attachment | Must |
| SE-02 | Results only show content the searcher may read | Must |
| SE-03 | Messages are indexed as one document each; open messages are re-indexed as they grow | Must |
| SE-04 | Public topics served as server-rendered HTML with clean URLs, sitemap, canonical links and discussion structured data; growing messages appear as single posts | Must |
| SE-05 | RSS/Atom feeds per category, topic and tag, listing closed messages only | Must |
| SE-06 | Topic lists: latest, most active, unanswered, per tag | Should |
| SE-07 | Search adapter interface so a large server can plug in an external search engine | Should |
| SE-08 | Related-topic and possible-duplicate suggestions when starting a topic | Could |

## 11. Notifications

A growing message produces one notification, so a burst of quick lines never becomes a burst of alerts.

| ID | Requirement | Priority |
| --- | --- | --- |
| NO-01 | In-app notification centre: mentions, replies, quotes, forks of your messages, activity in followed topics and categories | Must |
| NO-02 | A growing message notifies once, when it opens; an append notifies only someone newly @mentioned in it | Must |
| NO-03 | Levels per category and per topic: all, mentions only, none | Must |
| NO-04 | Email: instant or daily/weekly digest, sent from closed messages only; one-click unsubscribe | Must |
| NO-05 | Web push and mobile push without dependence on a single vendor relay | Should |
| NO-06 | Quiet hours per user | Should |

## 12. Accessibility and languages

The whole interface meets WCAG 2.2 level AA, including the live conversation view.

| ID | Requirement | Priority |
| --- | --- | --- |
| AX-01 | Full keyboard operation, visible focus, landmarks and headings on every page | Must |
| AX-02 | Screen readers announce a growing message when it opens and when it closes, not at every append | Must |
| AX-03 | The pencil icon, the countdown and the “view earlier version” tag have text equivalents | Must |
| AX-04 | Public pages readable without JavaScript | Must |
| AX-05 | Every interface string translatable; right-to-left languages supported | Must |
| AX-06 | Light, dark and high-contrast themes; text scaling; reduced motion | Should |
| AX-07 | Per-user language, time zone and date format; alt-text prompt on image upload | Should |

## 13. Administration and operations

After a one-command install, everything day-to-day is done in the web admin panel; the command line is only needed for recovery.

| ID | Requirement | Priority |
| --- | --- | --- |
| AD-01 | One-command install with containers (app, database, reverse proxy with automatic certificates); first-run wizard creates the owner account | Must |
| AD-02 | Web admin panel for settings, users, roles, categories, emoji, storage, email, appearance and legal pages | Must |
| AD-03 | Auto-archive setting: off by default; when on, a topic with no new message for 65 days becomes archived (read-only, still searchable). The period is editable in server-wide settings; moderators can reopen a topic | Must |
| AD-04 | Growing-message window: server default (45 s) and per-category override (GM-15) | Must |
| AD-05 | Scheduled backups to local disk or S3-compatible storage; restore from the admin panel or command line | Must |
| AD-06 | In-place upgrades with automatic database migrations and an automatic backup first | Must |
| AD-07 | File storage on local disk or S3-compatible storage, with per-user quotas | Must |
| AD-08 | SMTP settings with a test-send button | Must |
| AD-09 | Command-line tool for recovery: reset owner password, run backup or restore, check health | Must |
| AD-10 | phpBB importer: users, categories, topics, posts as closed messages, attachments, redirects from old URLs | Should |
| AD-11 | Branding: logo, colours, custom CSS | Should |
| AD-12 | Health page, structured logs and a metrics endpoint | Should |

## 14. Security and privacy

All traffic is encrypted between client and server; content is readable by the server so it can be moderated and searched. There is no end-to-end encryption and no private messaging.

| ID | Requirement | Priority |
| --- | --- | --- |
| SP-01 | HTTPS and secure WebSockets only (TLS 1.2 or later), certificates obtained and renewed automatically | Must |
| SP-02 | Passwords hashed with Argon2id; sessions in secure, HTTP-only cookies; API tokens scoped and revocable | Must |
| SP-03 | GDPR tooling: data export, erasure (messages anonymised or deleted, by user choice where law allows), consent records, retention settings | Must |
| SP-04 | No third-party scripts, fonts or analytics by default | Must |
| SP-05 | Content security policy, CSRF protection, rate limits on every endpoint, image metadata stripped on upload | Must |
| SP-06 | Admin audit log of every settings, role and permission change | Must |
| SP-07 | Published vulnerability disclosure policy and security-only patch releases | Must |
| SP-08 | Media proxy: external images and link previews fetched by the server, hiding users’ IP addresses | Should |
| SP-09 | Retention policies: auto-delete messages older than N days, per category | Should |

## 15. API, extensibility and federation readiness

The official web client uses the same public API as everyone else. Federation is not built in v1, but the data model and event system are shaped so it can be added without a rewrite.

| ID | Requirement | Priority |
| --- | --- | --- |
| AP-01 | Public REST API documented with OpenAPI | Must |
| AP-02 | Real-time event stream over WebSocket: message opened, appended, edited, closed; topic created, moved, archived | Must |
| AP-03 | Personal and application tokens with scopes | Must |
| AP-04 | Outgoing webhooks fire on closed messages and topic events; incoming webhooks post a closed message into a topic | Should |
| AP-05 | Bot accounts that post through the API, shown with a bot badge | Should |
| AP-06 | Plugin system with declared permissions, server hooks and interface slots | Could |
| FD-01 | Every user, category, topic and message has a globally unique, stable URI | Must |
| FD-02 | Internal events are recorded as activities (create, update, delete, announce) with actor, object and target, in an outbox | Must |
| FD-03 | Content stored as Markdown source plus sanitised HTML | Must |
| FD-04 | Each user and category gets a signing key pair at creation, for later server-to-server signatures | Should |
| FD-05 | Data model carries a local/remote origin on users and content (all local in v1) | Should |
| FD-06 | ActivityPub federation and chat bridges delivered as plugins | Could |

## 16. Clients

The web app is the only client required for v1; native apps come later on the same API.

| ID | Requirement | Priority |
| --- | --- | --- |
| CL-01 | Responsive web app for desktop and mobile browsers, installable as a progressive web app | Must |
| CL-02 | Lightweight server-rendered read view for public pages, working without JavaScript | Must |
| CL-03 | Keyboard shortcuts and a quick switcher for categories, topics and people | Should |
| CL-04 | Offline reading of recently opened topics | Should |
| CL-05 | Native iOS and Android apps that connect to any server by address | Could |

## 17. Non-functional requirements

These targets are agreed; a load test before each release verifies them.

| ID | Area | Target |
| --- | --- | --- |
| NF-01 | Live latency | New message or append shown to other viewers within 200 ms (95th percentile) |
| NF-02 | Durability | A commit is stored in the database before it is acknowledged; a restart loses no sent text |
| NF-03 | Page speed | Public topic page shows content in under 1 s on a mid-range phone over 4G |
| NF-04 | Minimum server | 2 vCPU, 2 GB RAM, 20 GB SSD for up to about 200 people online at once |
| NF-05 | Recommended server | 4 vCPU, 8 GB RAM for up to about 1,000 people online at once |
| NF-06 | Restart | Service back within 30 s; clients reconnect and catch up automatically |
| NF-07 | Backups | Daily by default, 14 days kept |
| NF-08 | Browsers | Current and previous version of major browsers, including mobile Safari |
| NF-09 | Portability | Full export as JSON plus Markdown plus original attachments |
| NF-10 | Quality | Automated tests cover every GM rule; accessibility audit and load test before each release |
| NF-11 | Documentation | Admin, moderator, user and API guides shipped with each release |

## 18. Proposed tech stack

Proposal: an Elixir/Phoenix application on PostgreSQL, behind Caddy, shipped as a Docker Compose bundle. It fits a server that holds thousands of live connections, runs a timer for every open message, and still serves plain HTML to readers and search engines — with only two required services besides the app.

&#91;embedded content: architecture · Docker Compose bundle\]

| Layer | Proposed choice | Why it fits |
| --- | --- | --- |
| Language and framework | Elixir with Phoenix | Built for many long-lived WebSocket connections; Channels and Presence cover live delivery and “who is reading” (TP-04, TP-16); scales to several nodes with built-in PubSub |
| Growing messages | One lightweight process per open message, holding its window timer; every commit written to the database first | A timer per message costs almost nothing on the Erlang VM; after a restart, open messages are rebuilt from the database (NF-02) |
| Web interface | Server-rendered HTML for public pages; Phoenix LiveView for the signed-in app; small JavaScript hooks for the composer and keys | Readers need no JavaScript (AX-04, CL-02), pages are indexable (SE-04), one codebase instead of a separate front-end app |
| Database | PostgreSQL | Relational data and permission checks; built-in full-text and trigram search (SE-01) |
| Background jobs | Oban (job queue stored in PostgreSQL) | Emails, digests, auto-archive, backups, webhooks without adding Redis |
| Search | PostgreSQL full-text by default; adapter for Meilisearch or OpenSearch | No extra service for small servers (SE-07) |
| File storage | Local disk or S3-compatible object storage | AD-07 |
| Reverse proxy and TLS | Caddy | Automatic certificates with minimal configuration (SP-01) |
| Email and push | SMTP via Swoosh; standard Web Push (VAPID) | Works with any mail provider; no vendor push relay (NO-05) |
| Authentication | Argon2id hashing, WebAuthn passkeys, TOTP, OpenID Connect client | SP-02, AC-03, AC-09 |
| Packaging | Docker Compose bundle (app, PostgreSQL, Caddy); standalone release for bare-metal installs | AD-01 |
| Observability | Built-in telemetry with a Prometheus metrics endpoint | AD-12 |

Alternative considered: a Go back end with a TypeScript single-page app. It is equally capable, but needs a separate server-rendering path for readers and search engines, and more front-end tooling to maintain.

### Building with Claude Code

The stack is confirmed on condition that Idejo can be built and maintained with Claude Code. Everything above runs from a terminal, which Claude Code needs. Elixir has less public code than JavaScript or Python, so written conventions and tests carry more weight in keeping generated code consistent.

| ID | Requirement | Priority |
| --- | --- | --- |
| DV-01 | The repository holds a CLAUDE.md with architecture, conventions, commands and the requirement IDs, updated with every change | Must |
| DV-02 | Every requirement ID has automated tests named after it (e.g. GM-03); all tests pass before a merge | Must |
| DV-03 | Formatter, linter, type checks, tests and accessibility checks all run from the command line and in CI | Must |
| DV-04 | Pinned versions of Elixir, Erlang, Phoenix and all dependencies; the full stack starts locally with one Docker Compose command | Must |
| DV-05 | Small changes: one requirement or fix per pull request, reviewed by a person before merge (also supports LI-08) | Must |
| DV-06 | Dependency audit on every build; human review of authentication, permission and upload code | Must |

## 19. Licensing

Idejo is released under the GNU AGPL-3.0-only, with one additional term under section 7(b): an attribution notice that must be preserved. Mariano Pictet holds the copyright as steward until an organisation is formed, which then takes it over; contributions are taken under an agreement that keeps a later dual-licensing option open.

| ID | Requirement |
| --- | --- |
| LI-01 | Every source file carries an SPDX header (AGPL-3.0-only); the full licence text ships in the repository and the install |
| LI-02 | Section 7(b) term: the attribution notice (product name and link to the project) shown in the interface’s legal notices must be preserved in modified versions; wording in the NOTICE file: “Powered by Idejo — © Mariano Pictet and contributors — AGPL-3.0”, linked to https://idejo.org |
| LI-03 | AGPL section 13: every server shows a “Source code” link in its footer pointing to the exact source it runs, including local modifications |
| LI-04 | Copyright steward: Mariano Pictet, as an individual, until an organisation is formed; the rights then transfer to it. A single steward keeps a second, commercial licence possible later |
| LI-05 | Licence-grant CLA, individual and corporate, based on the Apache ICLA/CCLA templates and signed once through an automatic check on pull requests: contributors keep their copyright but grant the steward, and any successor organisation, a perpetual, worldwide, royalty-free copyright and patent licence, including the right to relicense. A sign-off (DCO) alone is not enough for dual licensing |
| LI-06 | Only dependencies under licences compatible with both AGPL-3.0 and a future proprietary licence (e.g. MIT, BSD, Apache-2.0); checked automatically in CI |
| LI-07 | Trademark policy for the name “Idejo” and its logo, held by the steward |
| LI-08 | Human authorship of AI-assisted code: purely AI-generated code is not protected by copyright, while human selection, arrangement and modification are. So the steward writes the specifications (this document, kept in the repository), reviews and edits every change (DV-05), and AI-assisted commits carry a trailer such as “Assisted-by: Claude Code”. The AI tool’s terms must leave rights to its output with the user |

The setup uses standard templates and common practice, so no custom legal drafting is needed now; a lawyer reviews it before any commercial licence is offered.

## 20. Items still to confirm

- [x] All open questions are resolved; decisions are recorded in section 2.

**Sources** (licensing, section 19)

- [CLA vs. DCO: which contributor agreement to use](https://beancount.io/blog/2026/10/13/cla-vs-dco-contributor-agreement-open-source-project-guide)
- [US copyright law and AI — Apache Software Foundation](https://rai.apache.org/us-copyright-law.html)
- [US Copyright Office reaffirms human authorship in AI works](https://criticalplayground.org/us-copyright-office-reaffirms-human-authorship-in-ai-works/)
