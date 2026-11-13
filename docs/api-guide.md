<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# API guide

idejo's API v1 is for **the official idejo app** (`org.idejo.app`), and only for it: there
is one built-in client, no app registration, no personal tokens, no other clients and no
CORS. It reads and writes as the signed-in member would in the web app, through the same
rules, so whatever the web refuses, the API refuses with the same reason.

The exact reference is the OpenAPI document every forum serves at
`/api/v1/openapi.json` (OpenAPI 3.1, no token needed). This guide explains how the pieces
fit together.

Server administrators can turn the API off in **Admin → Settings → API and mobile app**
(on by default). Off, everything below answers 404, and the app should say so.

## 1. Discovery and adding a forum by address

The member types a forum's address. Ask, without signing in:

```sh
curl https://garden.example.org/.well-known/idejo
```

```json
{
  "name": "Garden club",
  "url": "https://garden.example.org/",
  "idejo_version": "0.3.6",
  "logo_url": "https://garden.example.org/logo",
  "api": {"versions": ["v1"], "base": "/api/v1", "openapi": "/api/v1/openapi.json",
          "socket": "/api/v1/socket"},
  "oauth": {"authorize": "/app/authorize", "token": "/api/v1/oauth/token",
            "revoke": "/api/v1/oauth/revoke", "client_id": "org.idejo.app",
            "redirect_uri": "org.idejo.app:/oauth/callback",
            "scopes": ["read", "write", "private", "moderate", "push"],
            "code_challenge_methods": ["S256"]},
  "community": {"directory_url": "https://forums.example.org/ or null"},
  "account": {"deletion_url": "https://garden.example.org/users/settings?tab=account#delete-heading",
              "sign_up_url": "https://garden.example.org/users/sign-up or null"},
  "features": ["unifiedpush", "gifs", "private_messages", "polls", "scheduled_messages"],
  "limits": {"page_size": 100, "requests_per_minute": 600, "upload_max_mb": 3,
             "devices_per_user": 20}
}
```

- Use https only. A server that answers without `api` is not an idejo server with the API.
- `"api": null` (with only `name` and `url`) means the administrator turned the API off.
- Paths are relative to the forum's address.

## 2. Signing in with PKCE

The app never sees a password. It opens the forum's own sign-in page in a **Custom Tab**,
so passwords, "Sign in with idejo ID" and anything the forum adds later all work.

1. Make a PKCE verifier (43 to 128 characters of `A-Z a-z 0-9 - . _ ~`) and its S256
   challenge, and a random `state`.

   ```sh
   VERIFIER=$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n' | cut -c1-64)
   CHALLENGE=$(printf %s "$VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=\n')
   ```

2. Open in a Custom Tab:

   ```
   https://garden.example.org/app/authorize?response_type=code
     &client_id=org.idejo.app
     &redirect_uri=org.idejo.app:/oauth/callback
     &scope=read%20write%20private%20moderate%20push
     &state=RANDOM&code_challenge=$CHALLENGE&code_challenge_method=S256
     &device_name=Pixel%208
   ```

   Anything wrong (another client id or redirect, no S256, a malformed challenge) shows an
   error page and never redirects. Not signed in, the member goes through the forum's
   normal sign-in (or sign-up, under the forum's registration rules) and comes back. Then
   the page asks "Sign in to the idejo app on this device as **Name**?" with **Allow** and
   **Cancel**.

3. The browser is sent to `org.idejo.app:/oauth/callback?code=…&state=RANDOM`, or with
   `error=access_denied` after Cancel. Check `state`. The code is valid 60 seconds, once.

4. Exchange it (form or JSON, no cookie; 10 a minute per address):

   ```sh
   curl https://garden.example.org/api/v1/oauth/token \
     -d grant_type=authorization_code -d code=$CODE \
     -d redirect_uri=org.idejo.app:/oauth/callback \
     -d client_id=org.idejo.app -d code_verifier=$VERIFIER
   ```

   ```json
   {"access_token": "idj_…", "token_type": "Bearer",
    "scope": "read write private moderate push", "token_id": "…", "user": {…}}
   ```

   There is no expiry and no refresh token. A code used twice is refused, and the token it
   gave is revoked.

Errors at the token endpoint use the API's one error shape (below), with the RFC 6749 names
as codes (`invalid_request`, `invalid_client`, `invalid_grant`, `unsupported_grant_type`):
`{"error": {"code": "invalid_grant", …}}`, not RFC 6749's `{"error": "invalid_grant"}`.

Several forums: sign in to each one separately. With idejo ID, the identity provider's
session makes each one a single tap.

## 3. Tokens, scopes and revocation

Send the token on every request: `Authorization: Bearer idj_…`. Nothing else: no cookie,
no session. Store it encrypted (Android Keystore); the server keeps only its hash.

Scopes: `read` (every GET), `write` (posting, editing, reacting, voting, following, the
profile), `private` (private conversations), `moderate` (moderation; the member must still
moderate the category), `push` (UnifiedPush). The app asks for all of them. A private
conversation reached through a topic or message path needs `private` too.

A token lasts until it is revoked:

- the app signs out: `POST /api/v1/oauth/revoke` with the token (always 204);
- the member removes the device under **Apps and devices** in Profile and account, or
  `DELETE /api/v1/me/tokens/{id}`;
- the password is reset or changed (from the web or the app: every device signs in again);
- the account is banned or deleted.

A user keeps at most 20 devices: a 21st sign-in revokes the oldest. A revoked token gets
`401 invalid_token`; the socket hears `token.revoked` and closes. A banned account gets
`403 banned` (for good) or `403 suspended` (until a date).

## 4. Conventions

- JSON in and out, UTF-8; times ISO 8601 in UTC; ids are strings; resources with a stable
  identity have a `uri` (FD-01) and a `url` to open in a browser.
- **Errors** have one shape:

  ```json
  {"error": {"code": "too_soon",
             "message": "You cannot post a new message yet. Append your old message.",
             "details": {}}}
  ```

  `code` is stable; `message` is the web app's own text, translated, ready to show.
  `details.fields` lists a form's problems (422), `details.until` a cooldown.

  | Status | When |
  | --- | --- |
  | 400 | Malformed request, bad cursor |
  | 401 | `unauthenticated`, `invalid_token` |
  | 403 | `insufficient_scope`, `banned`, `suspended`, `forbidden` (on something visible) |
  | 404 | `not_found`: missing **or not visible**, never telling which |
  | 409 | State conflicts: `too_soon`, `opening`, `taken`, `closed`, `cooldown`, … |
  | 410 | `cursor_expired` |
  | 413 | `too_large` (an image) |
  | 422 | `validation` and other refused values |
  | 429 | `rate_limited`, with `Retry-After` |

  Every code, with its status and text, is in the OpenAPI document under
  `x-idejo-error-codes`.
- **Pages**: `?cursor=…&limit=…` (50 by default, 100 at most) answer
  `{"data": […], "next_cursor": …, "prev_cursor": …}`. Cursors are opaque and signed;
  pass them back as they are.
- **Limits**: each action keeps the web's own limit (an Enter, a new message, a topic, a
  report, an upload, a reaction, a vote…), and each token has 600 requests a minute overall.
  Unauthenticated requests count per address.

## 5. The resource format and the Markdown dialect

Messages come as their Markdown source (`body_md`, exactly as stored) with structured
objects beside it, so the app never parses idejo's extensions to know what a message holds,
and never gets HTML:

- `mentions`: inline links, each `{type, text, id, slug, name}`; `type` is `user`, `role`,
  `topic`, `category` or `tag`. They were resolved as the author could see them.
- `images`: `{upload_id, url, alt, width, height}` (width and height for images uploaded
  since the API; GIFs have no `upload_id`).
- `spoiler`: `{"overlay": …}` for a message hidden behind a cover, or null;
  `inline_spoilers` when `||parts||` are hidden.
- `replies_to`: the message it replies to and the ones it quotes inline,
  `{message_id, author_name, excerpt, inline}`, only those the reader may read.
- `forwarded_from`: `{message_id, author_name, topic_id, topic_title, body_md, excerpt,
  visible}`; `visible: false` means "a message forwarded from a topic you cannot view".
- `poll`: question, options (`count` null while results are hidden), `my_votes`, `total`,
  `closes_at`, `closed`. Never who voted.
- `plugins`: the blocks under the message, `{command, block, params}` (`youtube`,
  `iframe`, `button`, `card`, `forum`; `collapse` is folded into the Markdown).
- `reactions`: `{emoji, name, char, image_url, count, mine}`.
- `state`: `open`, `closed` or `deleted`; `deleted_by`: `author` or `moderator`. A deleted
  message keeps its place; its text only for moderators of the category.
- `held`: closed early with Ctrl+Enter; `edited`, `moderator_edited`; `versions_count`
  (moderators only).
- `pinned_at`: when a moderator pinned it to the topic's navigator, or null. `GET
  /topics/{id}/pins` lists a topic's pinned messages, oldest pin first; with `moderate`,
  `PUT` and `DELETE /messages/{id}/pin` pin and unpin (logged; never in private
  conversations).
- `author`: name, user tag, pictures (`avatar_dark_url` for the dark theme), the role shown
  beside the name, `ignored_by_me` (collapse it, as the web does). An opening message of a
  topical topic has no author: `{"id": null, "display_name": "the topic", "topical": true}`.

idejo's Markdown is GitHub's (tables, strikethrough, task lists, bare links) plus:

| Write | Shows |
| --- | --- |
| `==highlight==` | highlighted |
| `x^2^` | superscript |
| `-# small` at the start of a line | small, faint text |
| `\|\|spoiler\|\|` | hidden until tapped |
| `:name:` | an emoji (`:tada:`, and the server's own, `GET /server` → `emoji`) |
| `@username` | a person |
| `+role` | everyone with that role (if the author may tag it) |
| `#topic-slug`, `/category-slug`, `$tag-slug` | a topic, a category, a tag |
| `&forum` | another forum of the author's, listed in the public directory: the first label of its address (`&garden` for `garden.idejo.org`), linked to `https://garden.idejo.org/` with the title `&garden.idejo.org`; `GET /suggest?sigil=&` gives `kind: "forum"`, its address as `id` |

Raw HTML is never rendered. Inline reply quotes are block quotes whose first line links to
the quoted message's permalink: `> [Replying to Ada:](/m/{id}) [excerpt](/m/{id})`.

### Topic permissions

A topic can override its category's rights for each role (`view`, `post`, `moderate`, and
`tag`, editing tags). With `moderate` there, `GET /topics/{id}/permissions` gives every
role but owner and administrator (who always have every right), with its own setting per
right (`own`: `allow`, `deny` or `unset`) and what the category gives it (`category`: true
or false). `PUT` the same path with `{"settings": {role_id: {right: "allow" | "deny" |
"unset"}}}`; roles and rights it does not know are left out, `moderate` is set last, and
each change is logged.

## 6. The growing message

A topic is a live chat whose lines grow into one message. The app's composer behaves like
the web's, and the server keeps every rule:

- **Typing**: on the first keystroke of a new message, `POST
  /topics/{id}/composer/typing` (or push `typing` on the topic channel). The server keeps
  the time on its own clock; the patience timers start there.
- **Enter**: `POST /topics/{id}/composer/commit` with the **whole** open message as the
  composer shows it: `{"body_md": "…", "break": false}`. The server stores it before
  answering, adds a full stop after unpunctuated text (unless the member turned automatic
  punctuation off), and answers the message and the composer's state. An Enter with nothing
  open opens a message.
- **Ctrl+Enter** (or Enter three times): the same with `"break": true`. Within the timers
  the message closes `held`: the next one waits until `held_until`.
- **Reply** while a message is open: `{"body_md": "the reply", "new": true, "reply_to":
  ["{message id}"]}`. It closes the open message and starts the reply, at once if
  `reply_allowed_early`, else `409 too_soon` until the timers run out. Forward with
  `"forward_of"`.
- **State**: `GET /topics/{id}/composer` answers `open_message_id`, `may_start_new_at`,
  `held_until`, `typing_since`, `window_seconds`, `unanswered_seconds`,
  `reply_allowed_early` and the server's `now`. Draw the countdown from these; never work
  the rules out in the app.
- **Edit** a closed message of one's own: `PUT /messages/{id}` with the whole text;
  `"finish": true` is Ctrl+Enter. One earlier version is kept per edit, however many
  Enters. Delete with `DELETE /messages/{id}` (not a topic's first message).
- Keep the topic channel joined while writing: if the author has no page or channel open
  on the topic for 30 seconds, their open message closes, as when a browser tab closes.

```
App                        Server                         Other members
 | typing ---------------> | keeps the first keystroke
 | commit "Hi" ----------> | stores, opens (closes_at fixed)
 | <------- message+state |  --- message.opened ------->  |
 | commit "Hi. Hello" ---> | stores the append
 | <------- message+state |  --- message.appended ----->  |
 | commit break:true ----> | closes (held if early)
 | <------- message+state |  --- message.closed ------->  |
 | GET composer ---------> | may_start_new_at, held_until
```

Private conversations work the same under `/conversations/{id}/composer/…`, with no slow
mode: `window_seconds` and `unanswered_seconds` are 0.

## 7. Events and catch-up

Connect a Phoenix Channels client (protocol 2.0.0) to `wss://<forum>/api/v1/socket/websocket`
with the params `{"token": "idj_…"}` (never in the address). The socket answers 403 to a bad
token and 404 while the API is off.

| Channel | Events |
| --- | --- |
| `user:me` | `notification`, `unread.changed`, `conversation.updated`, `scheduled.posted`, `token.revoked`, `settings.changed` |
| `topic:<id>` | `message.opened`, `message.appended`, `message.edited`, `message.closed`, `message.deleted`, `message.forked`, `reaction.changed`, `poll.updated`, `topic.updated`, `topic.moved`, `topic.archived`, `messages.moved`, `forbidden` |
| `conversation:<id>` | as `topic:<id>`, participants only (scope `private`) |
| `category:<id>` | `topic.created`, `topic.activity`, `topic.moved`, `topic.archived`, `forbidden` |

Joining needs the view right; a refused join answers `{"reason": "not_found"}`. A member
who loses the right gets `forbidden` and is left. Message events carry the whole message
object and its `cursor`. Typing is never broadcast. While a topic channel is joined, the
member gets no push about that topic.

**Catch-up**: a topic's join reply, its message window and every message carry a change
`cursor`. After a disconnect, `GET /topics/{id}/changes?since={last cursor}` returns every
message created, appended, edited, closed or deleted since (reactions and votes too), the
oldest change first, a page at a time (`more`). `410 cursor_expired` (a cursor from a
backup restored since) means: load the topic again. `messages.moved`: load the window
again.

## 8. UnifiedPush

With the `push` scope, register the distributor's endpoint and Web Push keys:

```sh
curl https://garden.example.org/api/v1/me/push/unifiedpush -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"endpoint": "https://ntfy.example.net/upXYZ", "p256dh": "<P-256 public key, base64url>",
       "auth": "<16 bytes, base64url>", "device_name": "Pixel 8"}'
```

- Any host, https on port 443, whose every address is public (no private, loopback,
  link-local, CGNAT, unique-local, multicast or mapped addresses), checked now and before
  every send. No redirects are followed.
- At most 10 browsers and devices per member; the registration ends with its token.
- `GET /me/push` lists them; `DELETE /me/push/unifiedpush/{id}`; `POST /me/push/test`.

Pushes are standard Web Push (RFC 8291 `aes128gcm`, VAPID RFC 8292), the same as the web's
(PN-01 to PN-16): decrypt with the keys you registered. The payload is declarative JSON:

```json
{"web_push": 8030,
 "notification": {"title": "Ada mentioned you in Garden plans", "body": "…excerpt…",
                  "navigate": "https://garden.example.org/m/{id}?unread",
                  "tag": "mentions", "lang": "en"},
 "app_badge": 3}
```

`tag` replaces an earlier notification with the same tag (`reply-{topic id}`, `mentions`,
`role-mentions`, `followed`, `private`, `warning`). Open `navigate` in the app. Distributors
that ignore VAPID still work.

## 9. Forums directory and "my forums"

- `GET /api/v1/me/communities`: the other forums the member joined in the same group (idejo
  Hub), `[{name, url, logo_url}]`, as the forum's community menu shows them. Empty on a
  standalone forum.
- Discovery's `community.directory_url` is the group's public directory page, or null. Its
  JSON is at `<directory_url>api/v1/forums?q=&page=`: listed forums with name, url,
  description, logo and member count, 20 a page.

## 10. Versioning

Everything here is v1. Within v1, changes are only additive: new endpoints, new fields in
answers, new events, new error codes. The app must ignore what it does not know. Fields are
never renamed or removed and meanings never change within v1; anything else would be v2,
listed in discovery's `api.versions` beside v1.

Account deletion stays on the web (`account.deletion_url`): members linked to idejo ID must
sign in there again first, which needs a browser.
