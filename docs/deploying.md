<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Deploying Idejo to a server

This guide takes you from an empty rented server to Idejo running at `https://your-domain`
with an automatic certificate. It is the M0 exit check: "an empty app deploys with HTTPS
from one command".

**You do not need PHP, Apache, nginx, Elixir or PostgreSQL on the server.** Everything runs
in three Docker containers defined in `deploy/docker-compose.yml`:

| Container | What it does |
| --- | --- |
| `caddy` | Receives web traffic on ports 80 and 443, gets and renews the HTTPS certificate (SP-01) |
| `app` | The Idejo release, built from the `Dockerfile` at the repository root |
| `db` | PostgreSQL 18, reachable only by the app |

The server only needs **Docker** and **git**.

Using **Infomaniak**? Follow the beginner's walkthrough in
[deploying-infomaniak.md](deploying-infomaniak.md) instead.

## What you need before you start

- **A server (VPS)** running **Debian 13 (trixie)**, with at least **2 vCPU and 2 GB RAM**
  (the pilot target) and 20 GB of disk. Any provider works (Hetzner, OVH, Infomaniak,
  DigitalOcean, Scaleway …). It must have a public IPv4 address.
- **A domain name** you control, for example `forum.example.org`. You will point it at the
  server.
- **An SSH key** on your own computer. If you have none, create one with
  `ssh-keygen -t ed25519` and give the provider the contents of `~/.ssh/id_ed25519.pub` when
  you create the server.
- **An email address** for certificate expiry notices from Let's Encrypt.

In the commands below, replace:

- `203.0.113.10` with your server's IP address,
- `forum.example.org` with your domain,
- `admin@example.org` with your email address.

## 1. Point your domain at the server

Do this first: DNS changes can take a while to spread, and Caddy can only get a certificate
once the name points at the server.

At your domain registrar or DNS provider, create:

| Type | Name | Value |
| --- | --- | --- |
| `A` | `forum` (or `@` for the bare domain) | `203.0.113.10` |
| `AAAA` | same as above | the server's IPv6 address — **only** if it has one |

Check from your own computer (it may take a few minutes to an hour):

```sh
dig +short forum.example.org        # must print 203.0.113.10
```

## 2. First login and a user for Idejo

Log in as `root` with the key you gave the provider:

```sh
ssh root@203.0.113.10
```

Update the system and turn on automatic security updates:

```sh
apt update && apt upgrade -y
apt install -y unattended-upgrades sudo rsync git curl ca-certificates ufw
dpkg-reconfigure -plow unattended-upgrades     # answer "Yes"
```

Create a normal user (here `idejo`) that can use `sudo`, and copy your SSH key to it:

```sh
adduser idejo                                  # choose a password; other questions can stay empty
usermod -aG sudo idejo
rsync --archive --chown=idejo:idejo ~/.ssh /home/idejo
```

Open a **second** terminal on your computer and check that this works before going on:

```sh
ssh idejo@203.0.113.10
sudo whoami                                    # prints "root"
```

Then switch off password and root logins over SSH. On the server, as `idejo`:

```sh
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
EOF
sudo systemctl restart ssh
```

From now on, always log in as `idejo`.

## 3. Firewall

Allow only SSH and web traffic (`ufw` was installed in step 2; Debian does not ship it):

```sh
sudo ufw allow 22/tcp                          # SSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp                         # HTTP/3
sudo ufw enable                                # answer "y"
sudo ufw status
```

If your provider also has a firewall in its web console, open the same ports there.

> Docker opens the ports it publishes (80 and 443 for Caddy) by itself, bypassing ufw. That
> is fine here: the database port is never published, so PostgreSQL is not reachable from
> the internet.

## 4. Swap (recommended on 2 GB servers)

Building the app image compiles Erlang code and needs memory for a few minutes. A swap file
stops the build from being killed:

```sh
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 5. Install Docker

Use Docker's own packages for Debian (Debian's `docker.io` is older and does not ship the
Compose plugin):

```sh
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker idejo
```

Log out and back in (so the `docker` group applies), then check:

```sh
docker run --rm hello-world
docker compose version
```

## 6. Get the code

```sh
git clone https://github.com/callisto-rpg/Idejo.git ~/idejo
cd ~/idejo
```

If the repository is private, create a read-only
[deploy key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)
for the server and clone with `git@github.com:callisto-rpg/Idejo.git` instead.

To deploy a branch that is not merged yet (e.g. for the M0 check), switch to it:

```sh
git switch m0-phoenix-app
```

## 7. Configure

```sh
cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
nano deploy/.env
```

Fill in every value (leave `IDEJO_SOURCE_URL` empty unless you changed the code):

| Variable | Value |
| --- | --- |
| `IDEJO_DOMAIN` | `forum.example.org` — exactly the name from step 1, no `https://` |
| `ACME_EMAIL` | `admin@example.org` |
| `SECRET_KEY_BASE` | output of `openssl rand -base64 48` (64 characters) |
| `POSTGRES_PASSWORD` | output of `openssl rand -hex 32` — hex only, because the password goes into a URL where `/` or `+` would break it |
| `IDEJO_SOURCE_URL` | empty for an unmodified Idejo: the "Source code" link in the footer (on the Help, profile and admin pages) then points at the exact upstream commit you built. If you run modified code, the AGPL requires that link to reach your source: publish it and put its address here |

`deploy/.env` holds your secrets. It is git-ignored and kept out of the Docker image; never
commit or share it. Keep a copy in your password manager: without `POSTGRES_PASSWORD` you
cannot reach the existing database, and changing `SECRET_KEY_BASE` signs everyone out.

## 8. Start Idejo

From `~/idejo`:

```sh
docker compose -f deploy/docker-compose.yml --env-file deploy/.env up -d --build
```

The first run builds the app image, which takes 5–15 minutes on a small server. Then the
app runs its database migrations and starts, and Caddy requests the certificate.

Follow progress:

```sh
docker compose -f deploy/docker-compose.yml --env-file deploy/.env ps        # app and db "healthy", caddy "running"
docker compose -f deploy/docker-compose.yml --env-file deploy/.env logs -f   # Ctrl+C to stop following
```

Look for `Access IdejoWeb.Endpoint at https://forum.example.org` from `app` and
`certificate obtained successfully` from `caddy`. Caddy starts only once `app` is healthy:
its health check asks `/health` every 15 seconds (see [Health endpoint](#health-endpoint)).

## 9. Check it

From your own computer:

```sh
curl -I https://forum.example.org
```

You should see `HTTP/2 302` with `location: /setup` (the server is not set up yet) and the
headers `strict-transport-security` (from Caddy) and `x-content-type-options` (from the app).
`curl https://forum.example.org/health` should answer `"status":"ok"`.
Open the address in a browser: the padlock should show a valid Let's Encrypt certificate,
and `http://` should redirect to `https://`.

## 10. Set up your server

Until it has an owner, every page of the server opens the setup wizard. So that nobody else
can claim your server first, the wizard asks for a setup code that only appears in the app
log:

```sh
docker compose -f deploy/docker-compose.yml --env-file deploy/.env logs app | grep -A2 "not set up yet"
```

Open the link it shows (`https://forum.example.org/setup?code=…`), or paste the code into the
wizard. The code changes each time the app restarts; if the link stops working, read the log
again.

The wizard asks for:

1. **The server name**, shown in the header and in emails.
2. **Your owner account**: email, username, display name and password. The owner has every
   right and can never be locked out; this account is ready to use straight away, without a
   verification email.
3. **Email**: see [Outgoing email](#outgoing-email). You can leave the SMTP host empty and set
   it up later in **Admin → Email**.

When you submit, you are signed in and taken to **Admin → Email**: press **Send test email**
to check that email works. The wizard is then gone for good.

Next, set up categories, roles and permissions with the [admin guide](admin-guide.md), and
give your members the one-page [member guide](member-guide.md).

### Or set it up from the command line

Instead of the wizard, `bin/idejo-admin setup` (AD-14) sets the server up in one command, for
scripts and for running many servers. It does exactly what the wizard does, except that the
owner gets no password here:

```sh
idejo exec app bin/idejo-admin setup --name "Garden Club" --owner-email you@example.org
```

| Option | Meaning |
| --- | --- |
| `--name NAME` | The server name (required, at most 80 characters). |
| `--owner-email EMAIL` | The owner's email (required). Their username is made from the part before `@` (`you`; letters, digits and `_`) and can never change; the display name, the same at first, can be changed in the profile. |
| `--registration open\|invite\|closed` | Who can sign up: anyone (the default, as with the wizard), only people with an invite, or nobody. Changeable later in **Admin → Settings**. |

The owner is created as an invite: an email takes them to a page where they choose their
password, within 7 days. While no SMTP server is set (neither **Admin → Email** nor
`IDEJO_SMTP_HOST`, see [Environment variables](#environment-variables)), the command prints
that link instead: give it to the owner yourself. If it expires unused, run
`bin/idejo-admin reset-owner-password` ([Recovery](#recovery-from-the-command-line)).

It exits with status 0 once the server is set up. On an already set-up server it changes
nothing and exits with 1; a missing or wrong option exits with 64. Audit entries of a
command-line setup name no admin, like the other commands.

## Prebuilt images

Each Idejo release is also published as a Docker image, `ghcr.io/callisto-rpg/idejo:X.Y.Z`
(and `X.Y` for the newest patch of that minor version), for linux/amd64. Idejo Hub uses these
images. The install above builds from source instead, so you do not need them for a
standalone server.

Releases are made by the steward: set `version` in `mix.exs`, merge, then push a tag with the
same number:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The "Publish image" workflow checks the tag against `mix.exs`, runs the M6 exit check and
only then pushes the image. An image built from a tag links to that exact commit as its
"Source code" (LI-03).

## Day-to-day operations

Run these from `~/idejo`. To save typing, define a shortcut once:

```sh
echo "alias idejo='docker compose -f ~/idejo/deploy/docker-compose.yml --env-file ~/idejo/deploy/.env'" >> ~/.bashrc
source ~/.bashrc
```

| Task | Command |
| --- | --- |
| Status | `idejo ps` |
| Logs of the app | `idejo logs -f app` |
| Restart the app | `idejo restart app` |
| Stop everything | `idejo down` (data is kept in Docker volumes) |
| Start again | `idejo up -d` |
| Health check | `idejo exec app bin/idejo-admin health` |
| A person leaves (sign-in provider) | `idejo exec app bin/idejo-admin leave --oidc-subject SUB` |
| Delete a person's account (sign-in provider) | `idejo exec app bin/idejo-admin delete-account --oidc-subject SUB` |
| Size (members, topics, messages, database, uploads; JSON) | `idejo exec app bin/idejo-admin stats` |

**Updating to a new version:** make a backup first (`idejo exec app bin/idejo-admin backup`,
see [Backups](#backups)), then:

```sh
cd ~/idejo
git pull
idejo up -d --build
```

Migrations run automatically when the app starts. The site is briefly unavailable while the
new app container replaces the old one.

The certificates live in the `caddy_data` volume; never delete it with `down -v`, or Caddy
has to request new ones and can hit Let's Encrypt rate limits. `down -v` would delete the
database, the images and the backups too.

## Backups

Every night at 03:00 UTC Idejo backs up the database and the uploaded images into one file,
`idejo-YYYYMMDD-HHMMSS.tar` (UTC), in the `backups` volume (`/data/backups` in the app
container). The newest 7 are kept; older ones are deleted. `idejo exec app bin/idejo-admin
health` shows when the last one was made; a failed backup is written to the app log.

At 04:00 UTC Idejo deletes uploaded images that nothing uses any more: pictures pasted into
a message and removed before sending, older than a day. Images in messages (deleted ones
and earlier versions included), in the About and Rules texts and avatars are kept.

**Make one now**, e.g. before an update:

```sh
idejo exec app bin/idejo-admin backup
idejo exec app bin/idejo-admin push-key
idejo exec app bin/idejo-admin rotate-push-keys
```

**Keep copies off the server.** A backup on the same disk does not survive the loss of the
server. Copy the backups out of the volume, then to another computer:

```sh
idejo cp app:/data/backups/. ~/idejo-backups               # on the server
scp -r idejo@203.0.113.10:idejo-backups ./               # on your computer
```

Keep a copy of `deploy/.env` with them, in your password manager: the SMTP password and the
push keys stored in the backup can only be read with the same `SECRET_KEY_BASE`. With
another key, everything works except email and push notifications until you enter the SMTP
password again in **Admin → Email** and run `bin/idejo-admin rotate-push-keys` (`health`
reports the push keys as unreadable until then; members' browsers subscribe again by
themselves).

### Restore a backup

Restoring replaces the whole database and every uploaded image with the backup's. Idejo
first backs up what is there now (the command prints that file's name), so a restore can be
undone by restoring that file. A backup made by a newer version of Idejo is refused: update
Idejo first.

1. Stop the app (the database keeps running):

   ```sh
   idejo stop app
   ```

2. Restore. A file name alone is looked for in the backups volume; the command asks you to
   type `restore` to confirm:

   ```sh
   idejo run --rm app bin/idejo-admin restore idejo-20261021-030000.tar
   ```

3. Start the app again; it runs the migrations a backup from an older version needs:

   ```sh
   idejo start app
   ```

Everyone has to sign in again only if they were signed in after the backup was made.

### Restore on another server

To move to a new server, or after losing one:

1. Install Idejo on the new server (steps 1 to 9), with the old `deploy/.env` if you have it
   (keep `IDEJO_DOMAIN`, and point the domain at the new server). Do not run the setup
   wizard: the backup brings your owner account back.
2. Copy the backup to the new server (on your computer:
   `scp idejo-20261021-030000.tar idejo@NEW-SERVER:`), then into the backups volume:

   ```sh
   idejo cp ~/idejo-20261021-030000.tar app:/data/backups/
   ```

3. Restore it as above: `idejo stop app`, `idejo run --rm app bin/idejo-admin restore
   idejo-20261021-030000.tar`, `idejo start app`.

## Recovery from the command line

Everything day-to-day happens in the web admin panel. When that is out of reach, the app
container carries a recovery tool, `bin/idejo-admin` (AD-09; it also runs
[the setup](#or-set-it-up-from-the-command-line), AD-14):

```sh
idejo exec app bin/idejo-admin health
idejo exec app bin/idejo-admin reset-owner-password
idejo exec app bin/idejo-admin backup
```

`restore` is described under [Restore a backup](#restore-a-backup).

If the app container is not running (it keeps restarting, or you stopped it), use
`idejo run --rm app bin/idejo-admin …` instead of `idejo exec app bin/idejo-admin …`.

**`health`** checks that the server is running, the database answers, every migration has
run, an owner exists, the push keys can be read, the uploads directory can be written and the last backup is less
than a day old, one line each. It ends with
exit status 1 when a check failed, so it can drive a monitoring script.

**`reset-owner-password [USERNAME]`** gives an owner a new random password and prints it
once. Every session of that account ends, open pages included. If the server has more than
one owner, name the one to reset; the command lists them. Sign in with the printed password,
then change it in your profile. The reset is recorded in the audit log.

Nothing else is needed: the command works without email and whether or not you remember the
owner's address.

**`push-key`** prints the server's public push key (VAPID), the one members' browsers
subscribe with. Every install makes its key pair when it first starts; backups carry it.

**`rotate-push-keys [--yes]`** makes a new key pair, after you type `rotate` (or with
`--yes`). Do it if the keys may have leaked, or when `health` says they cannot be read. Every
browser's push subscription ends; each subscribes again the next time its member opens a
page. The rotation is recorded in the audit log.

## Running behind your own reverse proxy

The bundle's Caddy is the default and the simplest: it gets certificates and passes every
request to the app. If the machine already runs a reverse proxy (nginx, Traefik, another
Caddy, a load balancer), or runs several Idejo servers behind one, leave Caddy out (AD-16)
with the second Compose file, given after the first:

```sh
docker compose -f deploy/docker-compose.yml -f deploy/docker-compose.external-proxy.yml \
  --env-file deploy/.env up -d --build
```

Use the same two `-f` options for every later command (or put them in the `idejo` alias of
[Day-to-day operations](#day-to-day-operations)). The second file changes only two things:
Caddy is not started, so ports 80 and 443 stay free, and the app is published on
`IDEJO_BIND:IDEJO_PORT`, `127.0.0.1:4000` unless you set them in `deploy/.env`.
`IDEJO_DOMAIN` is still required: links and the live connection check use it. `ACME_EMAIL`
is not used.

Your proxy must:

- terminate HTTPS for `IDEJO_DOMAIN` and pass requests to `http://127.0.0.1:4000` (or
  `IDEJO_BIND:IDEJO_PORT`), keeping the `Host` header;
- set `X-Forwarded-For` to the visitor's address, `X-Forwarded-Proto` to `https` and
  `X-Forwarded-Host` to the host name;
- pass WebSocket upgrades (the live pages use them, at `/live/websocket`) and keep them
  open for a long time;
- accept request bodies at least as large as the upload limit in **Admin → Settings**.

nginx:

```nginx
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
    listen 443 ssl;
    http2 on;
    server_name forum.example.org;
    ssl_certificate     /etc/letsencrypt/live/forum.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/forum.example.org/privkey.pem;
    client_max_body_size 20m;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 1h;
    }
}
```

Another Caddy (it sets the `X-Forwarded-*` headers by itself):

```caddyfile
forum.example.org {
	reverse_proxy 127.0.0.1:4000
}
```

**Which proxies the app believes.** The app takes the visitor's address (for its rate
limits), https and the host name from those headers only when the request comes from a
trusted proxy. From anyone else it ignores them, so nobody can pose as another address or
claim https. With `IDEJO_TRUSTED_PROXIES` empty, peers on a private network are trusted: a
proxy on the same machine reaches the app through Docker's network, so this works as it
is. If your proxy runs on another machine, publish the app on an address it can reach
(`IDEJO_BIND`, never a public one without a firewall) and set `IDEJO_TRUSTED_PROXIES` to
that proxy's address or range, comma-separated (`10.0.0.5`, `10.0.0.0/24`, `fd00::/8`).
Once set, only those addresses are trusted. A malformed value stops the app at boot with a
message saying so.

The app still sends HSTS and redirects plain `http` to `https` (except `/health`), and
builds every link from `IDEJO_DOMAIN`, never from the headers. Check it with
`curl https://forum.example.org/health`.

## Sign in through an OpenID Connect provider

Idejo can let people sign in with an account they already have at an OpenID Connect
provider (AC-09): Keycloak, Authentik, Dex, Zitadel, a company's or a family of forums'
own. Register Idejo there as a confidential web client with:

- **redirect URI** `https://forum.example.org/users/oidc/callback`;
- the **authorization code** flow with **PKCE** (S256);
- scopes `openid email profile`.

Then set, in `deploy/.env`:

```sh
IDEJO_OIDC_ISSUER=https://id.example.org          # the provider's issuer, https
IDEJO_OIDC_CLIENT_ID=forum
IDEJO_OIDC_CLIENT_SECRET=…                        # only here; never shown or logged
IDEJO_OIDC_LABEL=Example ID                       # the button: "Sign in with Example ID"
IDEJO_LOCAL_ACCOUNTS=on                           # off: no password sign-up or reset
```

and run the `up` command again. All four `IDEJO_OIDC_*` go together: some without the
others stop the app at boot with a message naming the missing ones. The provider's settings
and keys are fetched from its `/.well-known/openid-configuration` and kept up to date; if
it is down when the app starts, the app starts anyway and keeps asking.

What happens:

- **Accounts are linked by the provider's own id for the person** (issuer and subject),
  never by email. The first sign-in makes a member here, under **Who can sign up**: open,
  invite-only (the invite link's sign-up page has the button and carries the invite) or
  closed. Their username comes from the provider's `preferred_username` (or the email),
  their display name from `name`. An email the provider has not verified gets Idejo's
  verification email, as a sign-up would.
- **An account here with the same email is never joined by itself**: that sign-in is
  refused with a message. Its owner signs in with their password and presses **Link** in
  **Profile and account**.
- **The provider never gives a role.** Roles, the profile, bans and moderation history are
  this server's. A banned member stays banned, however they sign in.
- **Signing out** ends the session here only, not at the provider.
- **Deleting an account** without a password here asks the member to sign in at the
  provider again (within five minutes), instead of a password. The link goes with the
  account.

With `IDEJO_LOCAL_ACCOUNTS=off`, the sign-in page shows only the provider's button, sign-up
only through it, and there is no password reset by email. **Owners and administrators can
always sign in with a password** (the link under the button), so
`bin/idejo-admin reset-owner-password` keeps working ([Recovery](#recovery-from-the-command-line))
even when the provider is down. `IDEJO_LOCAL_ACCOUNTS=off` without the provider set up stops
the app at boot: nobody could sign in.

## Health endpoint

`GET /health` tells a monitoring tool, a container health check or an uptime service
whether the server works (AD-15). It needs no sign-in, sets no cookie, works before setup
and says nothing about your members:

```json
{"status": "ok", "version": "0.1.0", "checks": {"database": "ok", "migrations": "ok"}}
```

| Field | Values |
| --- | --- |
| `status` | `ok` when every check is ok, else `error` |
| `version` | the Idejo version running |
| `checks.database` | `ok`, or `error` when the database does not answer within 2 seconds |
| `checks.migrations` | `ok`; `pending` when the release has a migration not applied yet; `error` when they cannot be read |

The answer is `200 OK` when the status is `ok`, else `503 Service Unavailable`. It counts
toward the per-address limit of every request (300 a minute), far above any health check.
Unlike other pages it also answers over plain `http`, so the container's own check (in
`deploy/docker-compose.yml`) can ask it directly. For the reason behind an error, run
`bin/idejo-admin health` ([Recovery](#recovery-from-the-command-line)).

## Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| Caddy logs `challenge failed` or `no such host` | DNS does not point at the server yet (re-check `dig`, step 1), or ports 80/443 are closed in the provider's firewall. Caddy retries by itself. |
| Owner password lost, or email not set up for a reset link | `idejo exec app bin/idejo-admin reset-owner-password` (see [Recovery](#recovery-from-the-command-line)). |
| `app` stays "unhealthy" and Caddy does not start | `curl` cannot reach the app from outside yet, so look inside: `idejo logs app`, then `idejo exec app bin/idejo-admin health`. A database that does not answer or migrations that did not run are the usual causes. |
| `app` keeps restarting | `idejo logs app`. `SECRET_KEY_BASE is missing` or `DATABASE_URL` errors mean an empty value in `deploy/.env`. |
| `password authentication failed for user "idejo"` | `POSTGRES_PASSWORD` was changed after the first start. The database keeps the first password: restore the old value. |
| Build stops with `Killed` or exit code 137 | Out of memory: add swap (step 4) and run the `up` command again. |
| Browser shows "too many redirects" | Another proxy (e.g. Cloudflare in "Flexible" mode) sits in front. Set it to "Full (strict)", or turn the proxy off. Behind [your own reverse proxy](#running-behind-your-own-reverse-proxy): it does not send `X-Forwarded-Proto: https`, or the app does not trust it (`IDEJO_TRUSTED_PROXIES`). |
| Page loads but the live features do not connect | `IDEJO_DOMAIN` differs from the address in the browser (e.g. `www.` prefix): live connections are accepted only from `https://` and that exact name. Use exactly one name. |
| `app` stops with `PHX_HOST is missing` | Running without the bundled Compose file: set `PHX_HOST` to the public host name (see [Environment variables](#environment-variables)). |

## Outgoing email

Idejo sends sign-up verification emails (and later invites and password resets) through an
SMTP server you choose: your mail provider or a transactional email service. Once signed
in as an administrator, open **Admin → Email** and fill in:

- **Sender address**, e.g. `forum@example.org`. Use an address your SMTP service is allowed
  to send from, or messages will be rejected or land in spam.
- **SMTP host, port and encryption** from your provider: usually port 587 with STARTTLS, or
  465 with TLS from the start. Certificates are always checked.
- **Username and password**, if your provider requires a login. The password is stored
  encrypted with `SECRET_KEY_BASE`; if you ever change that key, enter the password again.

Save, then press **Send test email**: it goes to your own address. If it fails, the page
shows the reason. While no SMTP host is set, the server sends no email at all.

You can also give the server an SMTP server in `deploy/.env` (`IDEJO_SMTP_HOST` and the
other `IDEJO_SMTP_*` variables, see [Environment variables](#environment-variables)), for
example so the owner's first emails go out before anyone has signed in. It is used only
while **Admin → Email** has no SMTP host: the page then says so, showing its host and port
(never the login). As soon as a host is saved in the panel, the panel's settings are used
and the environment's are not; the two are never mixed. Change these variables, then run
the `up` command again.

## Environment variables

Every setting the app reads from its environment (AD-13). With the bundled Compose file you
only fill in `deploy/.env` (step 7); Compose sets the rest for the app. Running the image
some other way, set them yourself. A missing required variable stops the app at boot with a
message naming it.

| Variable | Required | Default | What it does |
| --- | --- | --- | --- |
| `PHX_HOST` | yes | none | The public host name, e.g. `forum.example.org` (no `https://`). Links, emails and the WebSocket origin check follow it. Compose sets it from `IDEJO_DOMAIN`. |
| `SECRET_KEY_BASE` | yes | none | Signs and encrypts cookies and stored secrets. Changing it signs everyone out and makes the saved SMTP password unreadable. |
| `DATABASE_URL` | yes | none | `ecto://USER:PASSWORD@HOST/DATABASE`. Compose builds it from `POSTGRES_PASSWORD`. |
| `PHX_SERVER` | no | off | `true` starts the web server; the image's `bin/server` sets it. |
| `PORT` | no | `4000` | Port the app listens on. |
| `POOL_SIZE` | no | `10` | Database connections kept open. |
| `ECTO_IPV6` | no | off | `true` or `1` to reach the database over IPv6. |
| `IDEJO_UPLOADS_DIR` | no | `/data/uploads` | Where uploaded images are kept. |
| `IDEJO_BACKUP_DIR` | no | `/data/backups` | Where nightly backups are written. |
| `IDEJO_PG_BIN_DIR` | no | the `PATH` | Where `pg_dump` and `pg_restore` are; they must match the database's major version. |
| `IDEJO_SOURCE_URL` | no | upstream at the built commit | The footer's "Source code" link. Required by the AGPL if you run modified code. |
| `IDEJO_SMTP_HOST` | no | none | SMTP server used while **Admin → Email** has no host. |
| `IDEJO_SMTP_PORT` | no | `587` | Its port. |
| `IDEJO_SMTP_SECURITY` | no | `tls` on port 465, else `starttls` | `starttls`, `tls` (TLS from the start) or `none` (a relay on the same machine or network only). Certificates are always checked. |
| `IDEJO_SMTP_USERNAME` | no | none | Its login, if it needs one. |
| `IDEJO_SMTP_PASSWORD` | no | none | Its password. Never stored, shown or logged by Idejo. |
| `IDEJO_SMTP_FROM` | no | the panel's sender address | Sender address while this server is in use. |
| `IDEJO_TRUSTED_PROXIES` | no | private networks | Reverse proxies whose `X-Forwarded-For`, `-Proto` and `-Host` are believed: IP addresses or CIDR ranges, comma-separated. See [Running behind your own reverse proxy](#running-behind-your-own-reverse-proxy). |
| `IDEJO_OIDC_ISSUER` | with the next three | none | The OpenID Connect provider's issuer (`https://…`). See [Sign in through an OpenID Connect provider](#sign-in-through-an-openid-connect-provider). |
| `IDEJO_OIDC_CLIENT_ID` | with the others | none | Idejo's client id at the provider. |
| `IDEJO_OIDC_CLIENT_SECRET` | with the others | none | Its client secret. Read from here only; never stored, shown or logged. |
| `IDEJO_OIDC_LABEL` | with the others | none | The provider's name on the button: "Sign in with …". |
| `IDEJO_OIDC_SIGN_UP_URL` | no | none | Where people without an account at the provider make one: "No … yet? Create one" under its button, on sign-in and sign-up. Only with the provider. |
| `IDEJO_ID_REGISTRY_URL` | no | `https://login.idejo.org` | The Idejo ID registry an administrator may connect the server to from **Admin → Idejo ID**, when no `IDEJO_OIDC_*` provider is set; `off` hides it. |
| `IDEJO_LOCAL_ACCOUNTS` | no | `on` | `off`: no password sign-up, sign-in or reset, except owners' and administrators' sign-in. Needs the provider. |
| `IDEJO_COMMUNITY_URL` | no | none | For a forum among several sharing one sign-in: where this server asks which other communities a member joined (`GET ?subject=`, HTTP Basic with the OpenID Connect client id and secret; JSON `{"communities": [{"name", "url"}]}`), shown in the forum icon's menu. Needs the provider. |
| `IDEJO_COMMUNITY_DIRECTORY_URL` | no | none | A public page listing those communities: "Find more forums" in the forum icon's menu. |
| `DNS_CLUSTER_QUERY` | no | none | For clustering several nodes; Idejo does not use it. |

`deploy/.env` itself also holds `IDEJO_DOMAIN`, `ACME_EMAIL` and `POSTGRES_PASSWORD`, which
Compose gives to Caddy and the database (step 7), and, only with
`deploy/docker-compose.external-proxy.yml`, `IDEJO_BIND` and `IDEJO_PORT`. Empty values
count as not set.

