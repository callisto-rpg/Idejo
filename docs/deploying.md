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

Fill in every value:

| Variable | Value |
| --- | --- |
| `IDEJO_DOMAIN` | `forum.example.org` — exactly the name from step 1, no `https://` |
| `ACME_EMAIL` | `admin@example.org` |
| `SECRET_KEY_BASE` | output of `openssl rand -base64 48` (64 characters) |
| `POSTGRES_PASSWORD` | output of `openssl rand -hex 32` — hex only, because the password goes into a URL where `/` or `+` would break it |

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

You should see `HTTP/2 200` with the headers `strict-transport-security` (from Caddy) and
`x-content-type-options` (from the app). Open the address in a browser: the padlock should
show a valid Let's Encrypt certificate, and `http://` should redirect to `https://`.

If both are true and CI is green, the M0 exit check passes.

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

**Updating to a new version:**

```sh
cd ~/idejo
git pull
idejo up -d --build
```

Migrations run automatically when the app starts. The site is briefly unavailable while the
new app container replaces the old one.

**Backing up by hand.** Nightly backups and restore (AD-05) arrive in M5. Until then, take a
database dump before every update:

```sh
mkdir -p ~/backups
idejo exec -T db pg_dump -U idejo -Fc idejo > ~/backups/idejo-$(date +%F).dump
```

Copy the dumps off the server from time to time (e.g. `scp` to your computer). The
certificates live in the `caddy_data` volume; never delete it with `down -v`, or Caddy has to
request new ones and can hit Let's Encrypt rate limits.

## Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| Caddy logs `challenge failed` or `no such host` | DNS does not point at the server yet (re-check `dig`, step 1), or ports 80/443 are closed in the provider's firewall. Caddy retries by itself. |
| `app` keeps restarting | `idejo logs app`. `SECRET_KEY_BASE is missing` or `DATABASE_URL` errors mean an empty value in `deploy/.env`. |
| `password authentication failed for user "idejo"` | `POSTGRES_PASSWORD` was changed after the first start. The database keeps the first password: restore the old value. |
| Build stops with `Killed` or exit code 137 | Out of memory: add swap (step 4) and run the `up` command again. |
| Browser shows "too many redirects" | Another proxy (e.g. Cloudflare in "Flexible" mode) sits in front. Set it to "Full (strict)", or turn the proxy off. |
| Page loads but the live features do not connect | `IDEJO_DOMAIN` differs from the address in the browser (e.g. `www.` prefix). Use exactly one name. |

## Not configured yet

- **Outgoing email** (invites, password reset) arrives with accounts in M1; the server needs
  no mail setup until then.
- **First-run wizard** (AD-01) also arrives in M1. For M0, the generated start page is what
  you should see.
