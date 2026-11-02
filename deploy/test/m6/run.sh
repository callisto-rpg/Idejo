#!/bin/sh
# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# M6 exit check (MVP §7), one command, Docker required:
#
#   deploy/test/m6/run.sh [--skip-flow]
#
# Two Idejo instances from one image behind one Caddy, set up with bin/idejo-admin setup,
# /health on both, one member signed in to both through Dex with a different role on each,
# no session cookie crossing hosts; then the "admin sets up the server" flow (mix, unless
# --skip-flow: CI runs it in its Tests job) and the default Compose install. Everything is
# removed at the end, pass or fail; any failure exits non-zero. See README.md.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
skip_flow=false
[ "${1:-}" = "--skip-flow" ] && skip_flow=true

work=$(mktemp -d)
chmod 755 "$work"
image=idejo-m6:check
check=idejo-m6
default=idejo-m6-default
browser=idejo-m6-browser

compose() { docker compose -p "$check" -f "$here/docker-compose.yml" --env-file "$work/env" "$@"; }
default_compose() {
  docker compose -p "$default" -f "$root/deploy/docker-compose.yml" --env-file "$work/default.env" "$@"
}

cleanup() {
  status=$?
  trap - EXIT INT TERM
  echo "==> Removing everything"
  docker rm -f "$browser" >/dev/null 2>&1 || true
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  default_compose down -v --remove-orphans >/dev/null 2>&1 || true
  [ -f "$work/failure.png" ] && cp "$work/failure.png" "$here/failure.png" && echo "Screenshot: $here/failure.png"
  rm -rf "$work"
  if [ "$status" -eq 0 ]; then echo "M6 exit check passed."; else echo "M6 exit check FAILED."; fi
  exit "$status"
}
trap cleanup EXIT INT TERM

step() { printf '\n==> %s\n' "$*"; }
secret() { head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

cat >"$work/env" <<ENV
IDEJO_M6_IMAGE=$image
IDEJO_M6_CA_BUNDLE=$work/ca-bundle.crt
POSTGRES_PASSWORD=$(secret)
FORUM_A_PASSWORD=$(secret)
FORUM_B_PASSWORD=$(secret)
FORUM_A_SECRET_KEY_BASE=$(secret)$(secret)
FORUM_B_SECRET_KEY_BASE=$(secret)$(secret)
FORUM_A_OIDC_SECRET=$(secret)
FORUM_B_OIDC_SECRET=$(secret)
ENV
touch "$work/ca-bundle.crt"

step "1. One image, built once"
docker build -q -t "$image" "$root" >/dev/null

step "1. Database (two databases, two roles), test provider and Caddy"
compose up -d --wait db dex caddy

# Caddy makes its internal CA with the first certificate it issues: ask for one.
for _ in $(seq 1 30); do
  compose exec -T caddy wget -q -O /dev/null --no-check-certificate https://id.idejo.test/.well-known/openid-configuration 2>/dev/null && break
  sleep 1
done
compose cp caddy:/data/caddy/pki/authorities/local/root.crt "$work/root.crt"
# The apps trust it as one more authority (mounted over the system's list; the image is not changed).
docker run --rm --entrypoint cat "$image" /etc/ssl/certs/ca-certificates.crt >"$work/ca-bundle.crt"
cat "$work/root.crt" >>"$work/ca-bundle.crt"

step "1. Two forums from the same image: a.idejo.test and b.idejo.test"
compose up -d --wait a b
[ "$(compose images -q a)" = "$(compose images -q b)" ] || { echo "a and b run different images"; exit 1; }

step "2. Set up with bin/idejo-admin setup, no wizard"
compose exec -T a bin/idejo-admin setup --name "Forum A" --owner-email owner-a@idejo.test
compose exec -T b bin/idejo-admin setup --name "Forum B" --owner-email owner-b@idejo.test --registration invite
# Forum B is invite-only: the member gets in through an invite, as any newcomer would.
invite=$(compose exec -T b bin/idejo rpc '
  owner = Idejo.Repo.get_by!(Idejo.Accounts.User, email: "owner-b@idejo.test")
  {:ok, invite} = Idejo.Accounts.create_invite(owner)
  IO.write(invite.code)' | tail -n 1)
[ -n "$invite" ] || { echo "no invite made on B"; exit 1; }

step "3. GET /health through Caddy on both"
for host in a.idejo.test b.idejo.test; do
  body=$(compose exec -T caddy wget -q -O - --no-check-certificate "https://$host/health")
  echo "  $host: $body"
  echo "$body" | grep -q '"status":"ok"' || { echo "$host is not healthy"; exit 1; }
done

step "4, 5. One member, both forums, through Idejo ID (Dex), in a browser"
network="${check}_m6"
docker run -d --name "$browser" --network "$network" \
  -e "B_INVITE=$invite" \
  -v "$here/browser:/w:ro" -v "$work:/out" \
  mcr.microsoft.com/playwright:v1.49.1-noble \
  sh -c 'mkdir -p /tmp/m6 && cp /w/check.mjs /tmp/m6/ && cd /tmp/m6 &&
         npm init -y >/dev/null && npm install --no-audit --no-fund --silent playwright@1.49.1 &&
         node check.mjs' >/dev/null

for _ in $(seq 1 300); do
  [ -f "$work/signed-in" ] && break
  [ "$(docker inspect -f '{{.State.Running}}' "$browser")" = "true" ] || break
  sleep 1
done

if [ -f "$work/signed-in" ]; then
  # An administrator's role change on A only (RP-06, audited, by A's owner).
  id_a=$(compose exec -T a bin/idejo rpc '
    member = Idejo.Repo.get_by!(Idejo.Accounts.User, email: "member@idejo.test")
    owner = Idejo.Repo.get_by!(Idejo.Accounts.User, email: "owner-a@idejo.test")
    {:ok, _} = Idejo.Access.assign_role(owner, member, Idejo.Access.built_in_role!(:moderator))
    IO.write(member.id)' | tail -n 1)
  id_b=$(compose exec -T b bin/idejo rpc '
    IO.write(Idejo.Repo.get_by!(Idejo.Accounts.User, email: "member@idejo.test").id)' | tail -n 1)
  printf '{"a": "%s", "b": "%s"}' "$id_a" "$id_b" >"$work/ids.tmp" && mv "$work/ids.tmp" "$work/ids"
fi

browser_status=$(docker wait "$browser")
docker logs "$browser" 2>&1 | grep -v '^npm' || true
[ "$browser_status" -eq 0 ] || { echo "the browser check failed"; exit 1; }

step "6. The single-server \"admin sets up the server\" flow"
if [ "$skip_flow" = true ]; then
  echo "  skipped (--skip-flow)"
else
  (cd "$root" && mix test --only flow:admin-sets-up-the-server)
fi

step "6. The default Compose install, unchanged: app, database and the bundled Caddy"
compose down -v --remove-orphans >/dev/null
cat >"$work/default.env" <<ENV
IDEJO_DOMAIN=default.idejo.test
ACME_EMAIL=admin@idejo.test
IDEJO_SOURCE_URL=
SECRET_KEY_BASE=$(secret)$(secret)
POSTGRES_PASSWORD=$(secret)
ENV
docker tag "$image" "${default}-app"
default_compose up -d --no-build --wait app
default_compose up -d --no-build caddy
default_compose ps --format '{{.Service}} {{.State}} {{.Health}}'
[ "$(default_compose ps --status running --services | sort | tr '\n' ' ')" = "app caddy db " ] ||
  { echo "the default install does not run app, caddy and db"; exit 1; }
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: default.idejo.test' http://127.0.0.1/ || true)
echo "  Caddy on port 80 answers $code (to https)"
case $code in 301 | 302 | 308) ;; *) echo "the bundled Caddy does not answer"; exit 1 ;; esac
