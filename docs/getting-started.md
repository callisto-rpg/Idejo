<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Getting started (M0)

These steps take the repository from the starter files to the M0 exit check: an empty app
that deploys with HTTPS from one command, with CI green.

## 0. On Windows, work inside WSL 2

Phoenix development is much smoother on Linux: Erlang compiles natively, `argon2_elixir`
needs a C compiler, and live reload needs `inotify-tools`. Install WSL 2 with Ubuntu
(`wsl --install` in an admin PowerShell), plus Docker Desktop with WSL integration on.
Clone the repository **inside** the Linux file system (e.g. `~/code/idejo`), not under
`/mnt/c/...`, or file watching and compiles will be slow.

## 1. Install the toolchain

```sh
sudo apt update
sudo apt install -y build-essential autoconf m4 libncurses-dev libssl-dev \
  libwxgtk3.2-dev libgl1-mesa-dev libglu1-mesa-dev libpng-dev libssh-dev \
  unixodbc-dev xsltproc fop libxml2-utils inotify-tools git curl
curl https://mise.run | sh            # then follow its instruction to activate mise
cd ~/code/idejo
mise install                          # Erlang + Elixir pinned in .tool-versions
mix local.hex --force
mix local.rebar --force
mix archive.install hex phx_new --force
pipx install reuse                    # or: pip install --user reuse
```

Install Claude Code with its official installer.

## 2. Generate the Phoenix app into this repository

```sh
mix phx.new . --app idejo --module Idejo
```

Answer **Y** when asked to continue in an existing directory. The generator does not touch
the starter files (CLAUDE.md, NOTICE, deploy/, .github/ …).

## 3. Add the M0 dependencies

In `mix.exs`, add to `deps`:

```elixir
{:oban, "~> x.y"},
{:argon2_elixir, "~> x.y"},
{:credo, "~> x.y", only: [:dev, :test], runtime: false},
{:dialyxir, "~> x.y", only: [:dev, :test], runtime: false},
{:sobelow, "~> x.y", only: [:dev, :test], runtime: false},
{:mix_audit, "~> x.y", only: [:dev, :test], runtime: false}
```

Replace each `x.y` with the current version from `mix hex.info <package>`. Then add the
Dialyzer PLT location to `project/0` (`dialyzer: [plt_local_path: "priv/plts"]`), add
`/priv/plts/` and `/deploy/.env` to `.gitignore`, and extend the generated `precommit` alias with
`"credo --strict"`, `"sobelow --config"` and `"deps.audit"`.

```sh
mix deps.get
mix credo gen.config
mix sobelow --save-config
```

## 4. Add SPDX headers and licence files

Add the two-line SPDX header to every generated `.ex`, `.exs`, `.heex`, `.js` and `.css`
file (Claude Code can do this in one pass), then:

```sh
reuse download AGPL-3.0-only    # creates LICENSES/AGPL-3.0-only.txt if missing
reuse lint
```

## 5. Run it locally

```sh
docker compose up -d     # dev PostgreSQL
mix setup
mix phx.server           # http://localhost:4000
mix precommit
```

## 6. Production bundle and the M0 exit check

```sh
mix phx.gen.release --docker      # creates Dockerfile and bin/migrate, bin/server
cp deploy/.env.example deploy/.env  # fill in domain, secrets
docker compose -f deploy/docker-compose.yml --env-file deploy/.env up -d --build
```

On a server whose DNS points at `IDEJO_DOMAIN`, the app is served over HTTPS.

## 7. Before the first pull request

- Write `docs/legal/CLA.md` (individual + corporate, based on the Apache ICLA/CCLA, LI-05).
  The CLA workflow links to it.
- On GitHub: protect `main` and require the CI and CLA checks to pass before merging.
- Tick M0 in CLAUDE.md once CI is green and the HTTPS deploy works.
