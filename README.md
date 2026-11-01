# Idejo

Idejo is a forum application, which attempts to provide all the best parts of independently-hosted forums of old with live chat communication platforms. The append-based message system aims to combine instant communication with the advantages of slower, long-form discussions.

Forums can be self-hosted on a VPS, or hosted on idejo.org per request.

## Learn more

* **Example server** and **meta-discussions**: https://forum.idejo.org/

## What it does

* **A forum where every topic is a live chat.** Communities are organised in categories and topics, like a classic forum. Inside a topic, lines sent with Enter join one **growing message**, so a quick exchange reads like a forum thread instead of a scroll of fragments. Ctrl+Enter starts a new message.
* **Everything around the conversation**: replies with quotes, reactions, polls, spoilers, scheduled messages, images, @mentions and +role tags, tags on topics, full-text search, unread tracking and follows, private conversations, and web push notifications.
* **Moderation built in**: reports, a moderation log, locking, pinning, moving and archiving topics, moving messages, bans, and automessages for common replies.
* **Run by its community**: roles with their own colours, a permission grid per category, invites, a first-run setup wizard, nightly backups and command-line recovery.
* **Light and open**: public pages work without JavaScript, there are no third-party scripts, fonts or trackers, and the code is free software.

## Host your own

Idejo runs on a small VPS (2 vCPU, 2 GB RAM is enough to start) with only Docker and git installed. Docker Compose runs the app, PostgreSQL and Caddy, and Caddy gets the HTTPS certificate for you.

* [Deploying Idejo to a server](docs/deploying.md), step by step ([on Infomaniak](docs/deploying-infomaniak.md))
* [Admin guide](docs/admin-guide.md): the admin panel, permissions and moderation
* [Member guide](docs/member-guide.md): the keys and the composer, on one page

## Develop

Idejo is written in Elixir with Phoenix and LiveView, on PostgreSQL. With the versions in `.tool-versions` installed (`mise install`) and Docker running:

```sh
docker compose up -d   # PostgreSQL for development
mix setup              # dependencies, database, assets
mix phx.server         # http://localhost:4000
mix test
```

[Getting started](docs/getting-started.md) covers the whole toolchain, including Windows (WSL 2). Before opening a pull request, read [CONTRIBUTING.md](CONTRIBUTING.md): contributors sign the [Contributor Licence Agreement](docs/legal/CLA.md) once.

## Licence

Idejo is licensed under the [GNU Affero General Public License v3.0 only](LICENSE). If you run a modified version for others, you must offer them its source code: set `IDEJO_SOURCE_URL` so the "Source code" link in every page's footer points to your version. The Idejo logos, the reaction images and the bundled fonts and emoji have licences of their own, listed in [NOTICE](NOTICE).
