<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# API v1: design record (AP-07 to AP-20)

The working plan for the official app's API (steward decision, 2026-11-10). Kept in the
branch as the record of the design; `docs/api-guide.md` is what the app developer reads.

## Layers

```
lib/idejo/accounts/api_token.ex, api_code.ex, api_tokens.ex   AP-08, AP-09: codes, tokens, revocation
lib/idejo/api.ex, lib/idejo/api/                              data the API returns, built in one place
  api/client_state.ex     server-side composer state between requests (typing time, edit sessions)
  api/changes.ex          change cursors (AP-16)
  api/resources.ex        batch loaders: topic decorations, message structure (AP-11)
lib/idejo/push/unified_push.ex                                AP-19 endpoint checks for any host
lib/idejo_web/api/                                            operations, OpenAPI, JSON, errors, plugs
lib/idejo_web/controllers/api/                                one controller per resource group
lib/idejo_web/channels/                                       ApiSocket and its channels (AP-15)
lib/idejo_web/controllers/app_authorize_controller.ex         /app/authorize (HTML)
```

Controllers and channels hold no rules: parameters in, one context call with the token's user
first, JSON out. Where the web app kept state in a LiveView process (the first keystroke's
time, "this edit already kept its version"), the API keeps it in `Idejo.Api.ClientState`
(ETS, per user and topic or message, server clock only), read by the same context functions.

**One list of operations.** `IdejoWeb.Api.Operations` holds every operation as data (method,
path, controller, action, scope, parameters, body, response schema, errors). The router
generates the `/api/v1` routes from it, the scope plug reads each route's scope from it, the
OpenAPI document is built from it, and the generated tests (no token, revoked token, wrong
scope, invisible id) iterate it, so no endpoint can skip a check.

## Tables and migrations

| Migration | What | Locks |
| --- | --- | --- |
| `api_tokens` | id, user_id (cascade), name (64), scopes (text[]), token_hash (bytea, unique), last_used_at, inserted_at, revoked_at; index user_id | new table |
| `api_codes` | id, user_id (cascade), code_hash (unique), challenge, scopes, device_name, expires_at, used_at, token_id (nilify) | new table |
| `push_subscriptions.kind`, `.api_token_id` | `kind` text default `'web'` not null, `api_token_id` references api_tokens on delete cascade; index | small table |
| `messages.change_seq` | bigint, nullable (old rows null = before any cursor); sequence `message_change_seq`; trigger `BEFORE INSERT OR UPDATE` taking `pg_advisory_xact_lock` on the topic and setting `nextval`; index `(topic_id, change_seq)` **concurrently** | `ADD COLUMN` without default is metadata only |
| `uploads.width`, `.height` | integer, nullable (filled for new images) | small table |
| setting `api_enabled` | `Settings` definition, boolean, default true | none |

### Change cursor (AP-16)

A per-topic cursor needs changes in commit order. A global sequence alone is not enough: a
transaction may take value 10, commit after one that took 11, and a client that read 11 never
sees 10. The trigger takes a transaction-scoped advisory lock on the message's topic before
`nextval`, so within a topic values are handed out in commit order. `commit/4` already holds
the topic row lock, so the hot path waits for nothing new. Reactions and votes touch the
message row (`change_seq` only), so they are in the catch-up too.

Retention: the cursor lives on the rows, so nothing is ever dropped. `410 cursor_expired` is
for a cursor from the future (a restored backup): the app reloads the topic.

## Sign-in

`/app/authorize` (browser) → Allow (POST, CSRF) → `org.idejo.app:/oauth/callback?code&state`
→ `POST /api/v1/oauth/token` (PKCE S256) → `idj_…` token. Codes: 32 random bytes, SHA-256
stored, 60 s, single use; a reused code revokes its token. Tokens: 32 random bytes base64url,
`idj_` prefix, SHA-256 stored, no expiry, 20 live per user (a 21st revokes the oldest).

Revoked: sign-out from the app (`/oauth/revoke`), Remove (Profile and account, `DELETE
/me/tokens/:id`), password reset and change, ban, account deletion, leaving the Hub
(`leave_by_identity`). Revoking broadcasts `token.revoked` on the user's channel, then
disconnects the token's sockets (`api_tokens:<id>`), and deletes its UnifiedPush rows.

Authentication: `Authorization: Bearer idj_…` only, `:api_v1` pipeline (no session, no
cookies, no CSRF), user loaded by `Accounts.get_user_by_api_token/1` (active, not banned:
`banned` for good, `suspended` with an end date, 403).

## Route table

All under `/api/v1`. Scope `-` means no token needed. Full detail is in the OpenAPI document.

| Method and path | Scope | Context |
| --- | --- | --- |
| GET /openapi.json | - | `IdejoWeb.Api.OpenApi` |
| POST /oauth/token | - | `ApiTokens.exchange/2` |
| POST /oauth/revoke | - | `ApiTokens.revoke_by_token/1` |
| GET /server | read | `Settings`, `Access.self_select_roles/0`, `Emoji`, `Commands` |
| GET /me, PATCH /me | read, write | `Accounts.update_user_profile/2`, `update_user_bio/2`, `update_user_writing/2`, `update_user_private_messages/2` |
| PUT /me/password | write | `Accounts.update_user_password/3` |
| PUT, DELETE /me/avatar, /me/avatar-dark | write | `Accounts.set_avatar/3`, `remove_avatar/2` |
| GET, PATCH /me/notification-settings | read, write | `Digest`, `Push.update_preferences/2` |
| GET /me/tokens, DELETE /me/tokens/:id | read, write | `ApiTokens` |
| PUT, DELETE /me/roles/:role_id | write | `Access.set_self_roles/2` |
| POST /me/welcome | write | `Accounts.mark_welcomed/1` |
| GET /me/warnings, POST /me/warnings/acknowledge | read, write | `Warnings.pending/1`, `acknowledge/1` |
| GET /me/ignored | read | `Accounts.list_ignored/1` |
| GET /me/communities | read | `Community.communities/1` |
| GET /me/push, POST /me/push/unifiedpush, DELETE /me/push/unifiedpush/:id, POST /me/push/test | read, push | `Push` |
| GET /categories, /categories/:id, /categories/:id/topics, /categories/:id/pending | read | `Forum` |
| GET /topics/active, /topics (tags), /tags, /unread, /search, /suggest, /emoji, /gifs | read | `Forum`, `Tags`, `Reading`, `Search`, `Suggestions`, `Emoji`, `Gifs` |
| GET /users/:id, /roles/:slug | read | `Accounts`, `Access` |
| GET /topics/:id, /topics/:id/messages, /topics/:id/changes, /topics/:id/commands | read | `Forum`, `TopicWindow`, `Api.Changes`, `Commands` |
| POST /categories/:id/topics, PATCH /topics/:id | write | `Forum.create_topic/4`, `rename_topic/4`, `set_topic_tags/4` |
| PUT, DELETE /topics/:id/follow, /topics/:id/mute; POST /topics/:id/mark-unread; PUT /topics/:id/read | write | `Reading` |
| POST /topics/:id/composer/typing, /composer/commit; GET /topics/:id/composer | write, read | `Messages.typing/3`, `commit/4`, `composer/2` |
| GET, PUT, DELETE /messages/:id; GET /messages/:id/versions | read, write | `Forum.get_readable_message/2`, `Messages.edit/4`, `delete_own/2`, `list_versions/1` |
| POST, GET /topics/:id/scheduled; DELETE /scheduled/:id | write, read | `Scheduling` |
| PUT, DELETE /messages/:id/spoiler | write | `Messages.set_spoiler/4` |
| POST /messages/:id/new-topic | write | `Forum.create_topic/4` with `forked_from:` |
| GET /forward-targets | read | `Forwards.targets/3` |
| PUT, DELETE /messages/:id/reactions/:emoji; GET /messages/:id/reactions | write, read | `Reactions` |
| POST /topics/:id/polls; PUT /polls/:id/vote | write | `Polls` |
| POST /topics/:id/plugins/:command; GET /topics/:id/plugins/:command/forums | write, read | `Plugins` |
| POST /uploads | write | `Uploads.store_image/2` |
| POST /messages/:id/report | write | `Moderation.report_message/3` |
| PUT, DELETE /users/:id/ignore | write | `Accounts.ignore_user/2`, `unignore_user/2` |
| GET /automessages, POST /topics/:id/automessages/:name | read, write | `Automessages` |
| GET, POST /conversations; GET /conversations/:id, /messages, /changes, /composer; POST /conversations/:id/composer/typing, /commit | private | `Conversations`, `Messages` |
| GET /moderation/reports, PATCH /moderation/reports/:message_id | moderate | `Moderation` |
| GET /moderation/pending-topics, POST …/:id/approve, …/:id/reject | moderate | `Forum` |
| GET /moderation/log | moderate | `Moderation.list/2` |
| GET /topics/:id/moderation | moderate | `Forum.topic_menu/2`, `list_move_targets/2` |
| POST /topics/:id/lock, unlock, pin, unpin, archive, unarchive, move, mark-inactive, make-topical; PUT /topics/:id/icon; DELETE /topics/:id | moderate | `Forum` |
| PUT, DELETE /topics/:id/followed-by-everyone | moderate | `Forum.set_autofollow/3` |
| GET /topic-icons, GET /moderation/move-targets | moderate | `TopicIcons`, `Forum.search_move_targets/3` |
| POST /moderation/messages/move, /moderation/messages/delete; DELETE, PUT /moderation/messages/:id; POST /moderation/messages/:id/close | moderate | `Forum.move_messages/5`, `Messages` |
| POST /users/:id/warn, GET /users/:id/warnings, POST, DELETE /users/:id/ban | moderate | `Warnings`, `Accounts` |

Outside `/api/v1`: `GET /.well-known/idejo` (AP-07), `GET|POST /app/authorize` (AP-08),
`/api/v1/socket` (AP-15).

## Schemas

`Error`, `Page`, `Server`, `Me`, `UserCard`, `Author`, `Category`, `Topic`, `TopicRow`
(topic plus expanded fields), `Message`, `Poll`, `Reaction`, `Version`, `Composer`,
`CommitResult`, `Changes`, `Token`, `TokenGrant`, `PushRegistration`, `Report`, `LogEntry`,
`PendingTopic`, `Warning`, `Conversation`, `Suggestion`, `SearchHit`, `ForwardTarget`,
`Upload`, `Scheduled`, `NotificationSettings`, `Community`, `Discovery`.

## Events

Socket `/api/v1/socket`, token in the connect params. Channels and events:

- `user:me`: `unread.changed`, `notification` (mention, reply, role_mention, follow,
  reaction, warning, private), `conversation.updated`, `scheduled.posted`, `token.revoked`,
  `settings.changed`.
- `topic:<id>`, `conversation:<id>`: `message.opened`, `message.appended`, `message.edited`,
  `message.closed`, `message.deleted`, `reaction.changed`, `poll.updated`, `topic.updated`,
  `topic.moved`, `topic.archived`, `messages.moved`; `forbidden` then leave on a lost right.
  Client push: `typing`.
- `category:<id>`: `topic.created`, `topic.activity`, `topic.moved`, `topic.archived`.

The channels subscribe to the PubSub topics the LiveViews use and map events per member.

## Tests

| ID | Tests |
| --- | --- |
| AP-07 | discovery shape, switch off, no cookie |
| AP-08 | full flow, wrong client or redirect (page, no redirect), plain or missing PKCE, wrong verifier, expired code, reused code revokes, CSRF, banned, invite-only and closed registration |
| AP-09 | revocation on reset, change, ban, deletion, Remove (sockets and push too); 21st token; Profile section without JavaScript |
| AP-10 | generated from the operations: no token, revoked token, missing scope |
| AP-11 | message object, structured mentions, images, poll, spoiler, plugins, deleted text |
| AP-12, AP-13 | per action, API result and database state as the web path |
| AP-14 | the growing message against the real engine (list in the prompt), GM-09 web plus app |
| AP-15, AP-16 | each event, join refused, lost right, privacy of conversations, catch-up exact, no typing |
| AP-17 | generated: invisible id gives 404 like a missing id; error codes documented |
| AP-18 | per-token limit, per-action limit, page size |
| AP-19 | SSRF refusals, DNS change before send, payload, no push while joined, ends with token |
| AP-20 | off: 404 everywhere and sockets dropped; on again: tokens work |
| — | privacy scanner: no other user's email in any API response; contract tests (routes, keys) |
| flow | `app-session` |
