<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Deploying Idejo on Infomaniak — beginner's guide

This guide walks you through putting Idejo online with an **Infomaniak** domain and server,
one click and one command at a time. You do not need to know Linux: copy each command, paste
it, press Enter, and check that you see what the guide says you should see.

It is the Infomaniak version of [deploying.md](deploying.md); read that file if you want the
reasons behind each step or use another provider.

Allow about **one hour**, most of it waiting for things to install.

---

## Before you start: check you bought the right kind of hosting

Idejo runs in Docker, which needs a server you fully control. At Infomaniak that is a
**VPS**:

| Product in your Infomaniak account | Works for Idejo? |
| --- | --- |
| **VPS Lite** or **VPS Cloud** | ✅ Yes |
| Web Hosting, Starter hosting, Cloud Server (managed) | ❌ No — these run PHP websites, not Docker. Cancel within the trial period if you can and order a VPS instead. |

For the VPS, choose:

- **Operating system:** **Ubuntu 24.04 LTS**
- **Size:** at least **2 vCPU and 2 GB RAM**, 20 GB disk or more
- **SSH key:** see step 1 — ideally you add it while ordering

You will also need the **domain** you bought (we use `forum.example.org` as an example), and
an **email address** for certificate notices.

### Words you will meet

| Word | Meaning |
| --- | --- |
| **Manager** | Infomaniak's website where you manage your products: https://manager.infomaniak.com |
| **Terminal** | The window where you type commands. Called *Terminal* on macOS and Linux, *Windows Terminal* or *PowerShell* on Windows. |
| **SSH** | The way your terminal connects to the server. Once connected, commands run **on the server**. |
| **IP address** | Your server's number on the internet, like `203.0.113.10`. |

In every command below, replace:

- `203.0.113.10` with **your server's IP address**,
- `forum.example.org` with **your domain**,
- `admin@example.org` with **your email address**.

Lines starting with `#` are explanations; you can paste them too, they do nothing.

---

## Step 1 — Your SSH key

An SSH key is a pair of files that lets you log in to the server without a password. It lives
on **your computer**.

**On your computer**, open a terminal and check whether you already have one:

```sh
ls ~/.ssh/id_ed25519.pub
```

- If it prints the file name, you have one — go to the next paragraph.
- If it says `No such file or directory`, create one (press Enter at every question):

  ```sh
  ssh-keygen -t ed25519
  ```

Show the **public** half (the `.pub` file — never share the other one):

```sh
cat ~/.ssh/id_ed25519.pub
```

It is one long line starting with `ssh-ed25519`. You give this line to Infomaniak:

- **If you have not ordered the VPS yet:** paste it into the SSH key field of the order form.
- **If the VPS already exists:** in the Manager, open your VPS and look for the SSH key
  settings, or use the key Infomaniak generated for you and downloaded during ordering. In
  that case, use `ssh -i path/to/that-key ...` instead of plain `ssh ...` in step 4.

> **Windows:** Windows 10 and 11 include `ssh` and `ssh-keygen`. Use **Windows Terminal** or
> **PowerShell**; the commands above work, with `~` meaning `C:\Users\<you>`.

---

## Step 2 — Find your server's IP address

1. Log in to the **Manager**: https://manager.infomaniak.com
2. Open your **VPS** (search "VPS" in the Manager's menu or search bar).
3. Click your server's name. Note its **IPv4 address** (four numbers separated by dots).
   If an **IPv6** address is shown too, note it as well.

---

## Step 3 — Open the firewall

Infomaniak puts a firewall in front of every VPS. Idejo needs web traffic to reach it.

1. In the Manager, on your VPS page, click **Firewall** in the left-hand menu.
2. Check which rules already exist. You need all four of these; add each one that is
   missing with the blue **Add a rule** button, then **Manual selection**:

   | Protocol | Port | Source | What for |
   | --- | --- | --- | --- |
   | TCP | 22 | all (`0.0.0.0/0`) | SSH — you logging in |
   | TCP | 80 | all (`0.0.0.0/0`) | Web, and getting the certificate |
   | TCP | 443 | all (`0.0.0.0/0`) | HTTPS |
   | UDP | 443 | all (`0.0.0.0/0`) | HTTP/3 (faster HTTPS) |

3. Click **Confirm** after each rule.

> Do not limit port 22 to your home IP address unless you know it never changes: if it
> changes, you are locked out (rescue: the Manager's web console, see Troubleshooting).

---

## Step 4 — Point your domain at the server

This tells the internet that `forum.example.org` lives on your VPS. Do it now — it can take
from a few minutes up to a few hours to take effect.

1. In the Manager, open **Domains** and click your domain.
2. Click **DNS zone** in the left-hand menu.
3. Decide which address people will use:
   - a **subdomain** like `forum.example.org` → the record's name is `forum`;
   - the **bare domain** `example.org` → the record's name is empty (or `@`).
4. Look at the existing entries. If there is already an **A** record with that name (for
   example one Infomaniak created for a parking page or web hosting), **edit** it rather than
   adding a second one: two A records for one name send half your visitors elsewhere.
5. Otherwise click **Add entry**, choose **A**, and fill in:
   - **Source / name:** `forum` (or empty for the bare domain)
   - **Target / IPv4:** `203.0.113.10`
   - **TTL:** leave the default
6. Only if your VPS has an IPv6 address: add an **AAAA** record with the same name and the
   IPv6 address. If it has none, make sure no old AAAA record exists for that name.
7. Save.

Check from **your computer** (repeat every few minutes until it shows your IP):

```sh
nslookup forum.example.org
```

On macOS and Linux, `dig +short forum.example.org` also works.

---

## Step 5 — Log in to the server

**On your computer:**

```sh
ssh ubuntu@203.0.113.10
```

- The user is **`ubuntu`** — that is Infomaniak's default for Ubuntu servers.
- The first time, it asks *"Are you sure you want to continue connecting?"* — type `yes`.
- You are in when the prompt changes to something like `ubuntu@your-server:~$`.

From now on, **every command runs on the server** until the guide says otherwise. To leave
the server, type `exit`.

If it says `Permission denied (publickey)`, the server does not have your key: see
Troubleshooting.

---

## Step 6 — Update the server

```sh
sudo apt update && sudo apt upgrade -y
```

This can take a few minutes. If a purple screen asks about configuration files or restarting
services, press **Enter** to accept the default.

Turn on automatic security updates:

```sh
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Choose **Yes** with the arrow keys and press Enter.

If `apt upgrade` installed a new kernel, restart once, wait a minute, and log in again
(step 5):

```sh
sudo reboot
```

---

## Step 7 — Lock the server's door

Make sure nobody can log in with a password (only with your key):

```sh
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
EOF
sudo systemctl restart ssh
```

**Before closing your current window**, open a **second** terminal on your computer and
check you can still log in with `ssh ubuntu@203.0.113.10`. If you can, close the second
window and continue. If you cannot, undo it from the first window with
`sudo rm /etc/ssh/sshd_config.d/10-hardening.conf && sudo systemctl restart ssh`.

---

## Step 8 — Add swap memory

Building Idejo needs more memory than 2 GB for a few minutes. Swap lets the server borrow
disk space as memory so the build is not killed:

```sh
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Check: `free -h` shows a **Swap** line of about 2.0Gi.

---

## Step 9 — Install Docker

Paste this block as a whole:

```sh
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git
sudo usermod -aG docker ubuntu
```

Log out and back in, so your user may use Docker:

```sh
exit
```

```sh
ssh ubuntu@203.0.113.10
```

Check:

```sh
docker run --rm hello-world
```

You should see **"Hello from Docker!"**.

---

## Step 10 — Download Idejo

```sh
git clone https://github.com/callisto-rpg/Idejo.git ~/idejo
cd ~/idejo
```

---

## Step 11 — Fill in your settings

Create your settings file from the example and protect it:

```sh
cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

Generate two secrets and **copy each output somewhere safe** (a password manager):

```sh
openssl rand -base64 48
```

```sh
openssl rand -hex 32
```

Open the file in a simple editor:

```sh
nano deploy/.env
```

Move with the arrow keys and fill in the four values after the `=` signs, with no spaces
and no quotes:

```
IDEJO_DOMAIN=forum.example.org
ACME_EMAIL=admin@example.org
SECRET_KEY_BASE=<the first secret, from "rand -base64 48">
POSTGRES_PASSWORD=<the second secret, from "rand -hex 32">
```

Save with **Ctrl+O** then **Enter**, and leave with **Ctrl+X**.

> Keep these values safe. Without `POSTGRES_PASSWORD` you cannot reach your data, and
> changing `SECRET_KEY_BASE` signs everyone out. Never send this file to anyone.

---

## Step 12 — Start Idejo

Before starting, check once more that your domain points at the server (step 4): if not,
the certificate request fails (Caddy retries by itself, but it is quicker to wait).

```sh
cd ~/idejo
docker compose -f deploy/docker-compose.yml --env-file deploy/.env up -d --build
```

The first time takes **5 to 15 minutes**: it builds Idejo on the server. You will see many
lines scroll by. It is done when you get your prompt back with lines ending in `Started`.

Check that the three parts are running:

```sh
docker compose -f deploy/docker-compose.yml --env-file deploy/.env ps
```

You should see `app`, `caddy` and `db` with the status **Up** (and `db` **healthy**).

---

## Step 13 — Visit your site

Open **https://forum.example.org** in your browser. You should see the Idejo start page with
a **padlock** next to the address.

The very first visit can take up to a minute while the certificate is fetched. If it does
not work after a few minutes, see Troubleshooting.

🎉 Idejo is online with HTTPS. This is the M0 exit check.

---

## Everyday use

Log in with `ssh ubuntu@203.0.113.10`, then create a shortcut **once**:

```sh
echo "alias idejo='docker compose -f ~/idejo/deploy/docker-compose.yml --env-file ~/idejo/deploy/.env'" >> ~/.bashrc
source ~/.bashrc
```

| To … | Type |
| --- | --- |
| see if everything runs | `idejo ps` |
| read the app's messages | `idejo logs -f app` (stop reading with Ctrl+C) |
| restart Idejo | `idejo restart app` |
| stop everything | `idejo down` (your data is kept) |
| start again | `idejo up -d` |

### Updating to a new version

Make a backup first (below), then:

```sh
cd ~/idejo
git pull
idejo up -d --build
```

### Backups

Automatic nightly backups come in a later version (AD-05). Until then:

1. **Database copy on the server**, before every update:

   ```sh
   mkdir -p ~/backups
   idejo exec -T db pg_dump -U idejo -Fc idejo > ~/backups/idejo-$(date +%F).dump
   ```

2. **Copy the backups to your computer** from time to time. **On your computer:**

   ```sh
   scp -r ubuntu@203.0.113.10:backups ./idejo-backups
   ```

3. **Infomaniak snapshots:** on your VPS page in the Manager, **Snapshots** saves the whole
   server. Take one before big changes.

Never run `idejo down -v`: the `-v` deletes your database and certificates.

---

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `Permission denied (publickey)` when logging in | The server lacks your key. Check you used `ubuntu@` and the right IP. If Infomaniak generated the key, add `-i path/to/key`. Otherwise use the Manager's **web console** on the VPS page to log in and add the line from `cat ~/.ssh/id_ed25519.pub` to `/home/ubuntu/.ssh/authorized_keys`. |
| `Connection timed out` when logging in | Port 22 is not open in the Infomaniak firewall (step 3), or the IP is wrong. |
| Browser says "site can't be reached" | DNS not ready yet (`nslookup` in step 4 must show your IP), or ports 80/443 not open in the firewall (step 3). |
| Browser warns the certificate is invalid | Caddy has not got the certificate yet. Read `idejo logs caddy`. Messages with `challenge failed` mean DNS or the firewall is not right yet; fix them and wait — Caddy retries. |
| `idejo ps` shows `app` restarting | Read `idejo logs app`. `SECRET_KEY_BASE is missing` or a `DATABASE_URL` error means a value in `deploy/.env` is empty or has a space or quote. Fix it, then `idejo up -d`. |
| `password authentication failed for user "idejo"` | You changed `POSTGRES_PASSWORD` after the first start. Put the original value back. |
| The build stops with `Killed` | Not enough memory: do step 8 (swap), then run the step 12 command again. |
| "Too many redirects" | Something else sits in front of the server (e.g. a CDN or proxy option on the domain). Turn it off so the domain points straight at the VPS. |

## Good to know

- **Email:** Infomaniak blocks outgoing port 25 on every VPS (and it cannot be opened on
  VPS Lite). Set up email in **Admin → Email** with an SMTP service on port 587 (STARTTLS)
  or 465 (TLS), which are not blocked — see "Outgoing email" in `docs/deploying.md`.
- **Infomaniak support** helps with the Manager, the firewall and DNS, but a VPS is
  "unmanaged": they do not support the software you install on it.

Sources for the Infomaniak-specific steps: Infomaniak knowledge base —
[first SSH connection](https://www.infomaniak.com/en/support/faq/1973/connect-via-ssh-first-connection-vps-cloud-vps-lite-linux),
[VPS firewall](https://www.infomaniak.com/en/support/faq/2822/manage-vps-cloud-vps-lite-firewall),
[A and AAAA records](https://www.infomaniak.com/en/support/faq/2088/manage-a-and-aaaa-records).
