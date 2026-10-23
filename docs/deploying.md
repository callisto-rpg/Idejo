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

- **A server (VPS)** running **Ubuntu 24.04 LTS**, with at least **2 vCPU and 2 GB RAM**
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
apt install -y unattended-upgrades git curl
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

Allow only SSH and web traffic:

```sh
sudo ufw allow OpenSSH
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

Use Docker's own packages (the `docker.io` package from Ubuntu lacks the Compose plugin):

```sh
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
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
| `IDEJO_SOURCE_URL` | empty for an unmodified Idejo: the "Source code" link in the footer then points at the exact upstream commit you built. If you run modified code, the AGPL requires that link to reach your source: publish it and put its address here |

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
docker compose -f deploy/docker-compose.yml --env-file deploy/.env ps        # all three "running"/"healthy"
docker compose -f deploy/docker-compose.yml --env-file deploy/.env logs -f   # Ctrl+C to stop following
```

Look for `Access IdejoWeb.Endpoint at https://forum.example.org` from `app` and
`certificate obtained successfully` from `caddy`.

## 9. Check it

From your own computer:

```sh
curl -I https://forum.example.org
```

You should see `HTTP/2 302` with `location: /setup` (the server is not set up yet) and the
headers `strict-transport-security` (from Caddy) and `x-content-type-options` (from the app).
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
container carries a recovery tool, `bin/idejo-admin` (AD-09):

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

## Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| Caddy logs `challenge failed` or `no such host` | DNS does not point at the server yet (re-check `dig`, step 1), or ports 80/443 are closed in the provider's firewall. Caddy retries by itself. |
| Owner password lost, or email not set up for a reset link | `idejo exec app bin/idejo-admin reset-owner-password` (see [Recovery](#recovery-from-the-command-line)). |
| `app` keeps restarting | `idejo logs app`. `SECRET_KEY_BASE is missing` or `DATABASE_URL` errors mean an empty value in `deploy/.env`. |
| `password authentication failed for user "idejo"` | `POSTGRES_PASSWORD` was changed after the first start. The database keeps the first password: restore the old value. |
| Build stops with `Killed` or exit code 137 | Out of memory: add swap (step 4) and run the `up` command again. |
| Browser shows "too many redirects" | Another proxy (e.g. Cloudflare in "Flexible" mode) sits in front. Set it to "Full (strict)", or turn the proxy off. |
| Page loads but the live features do not connect | `IDEJO_DOMAIN` differs from the address in the browser (e.g. `www.` prefix). Use exactly one name. |

## Outgoing email

Idejo sends sign-up verification emails (and later invites and password resets) through an
SMTP server you choose: your mail provider or a transactional email service. Nothing goes
in `deploy/.env` for this. Once signed in as an administrator, open **Admin → Email** and
fill in:

- **Sender address**, e.g. `forum@example.org`. Use an address your SMTP service is allowed
  to send from, or messages will be rejected or land in spam.
- **SMTP host, port and encryption** from your provider: usually port 587 with STARTTLS, or
  465 with TLS from the start. Certificates are always checked.
- **Username and password**, if your provider requires a login. The password is stored
  encrypted with `SECRET_KEY_BASE`; if you ever change that key, enter the password again.

Save, then press **Send test email**: it goes to your own address. If it fails, the page
shows the reason. While no SMTP host is set, the server sends no email at all.

