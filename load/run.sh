#!/bin/sh
# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Load test (NF-01, NF-04), from the repository root:
#
#   load/run.sh [options for load/run.exs, e.g. --hot or --duration 300]
#
# Builds and starts the production bundle on 2 CPUs and 2 GB (load/docker-compose.load.yml),
# seeds it, runs load/run.exs on the other CPUs, samples the containers' CPU and memory, then
# removes everything, volumes included. Needs Docker, 4 CPUs or more, and Elixir (mise).
set -eu

work=$(mktemp -d)
compose="docker compose -p idejo-load -f deploy/docker-compose.yml -f load/docker-compose.load.yml --env-file $work/load.env"

cat > "$work/load.env" <<ENV
IDEJO_DOMAIN=localhost
ACME_EMAIL=load@example.org
SECRET_KEY_BASE=$(openssl rand -hex 64)
POSTGRES_PASSWORD=$(openssl rand -hex 32)
ENV

cleanup() {
  [ -n "${stats_pid:-}" ] && kill "$stats_pid" 2>/dev/null || true
  $compose down -v >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

$compose up -d --build app
until curl -s -o /dev/null http://localhost:4100/; do sleep 1; done
$compose exec -T app bin/idejo rpc 'Code.eval_file("/load/seed.exs")'

# CPU and memory of the app and the database, every 2 seconds, during the run.
# Each container on its own, and a failed sample never stops the sampling.
( set +e
  while true; do
    for c in idejo-load-app-1 idejo-load-db-1; do
      docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}}' "$c"
    done
    sleep 2
  done ) > "$work/stats.txt" 2>/dev/null &
stats_pid=$!

taskset -c 2-"$(($(nproc) - 1))" mix run --no-start load/run.exs --url http://localhost:4100 "$@"

kill "$stats_pid"; stats_pid=
for c in idejo-load-app-1 idejo-load-db-1; do
  docker inspect -f "$c: restarts {{.RestartCount}}, killed for memory {{.State.OOMKilled}}" "$c"
done
awk '
  { cpu = $2; sub("%", "", cpu); cpu += 0; mem = $3
    unit = mem; sub("[0-9.]+", "", unit); sub("[A-Za-z]+", "", mem); mem += 0
    if (unit == "GiB") mem *= 1024; if (unit == "KiB") mem /= 1024
    if (cpu > maxcpu[$1]) maxcpu[$1] = cpu; if (mem > maxmem[$1]) maxmem[$1] = mem
    sumcpu[$1] += cpu; n[$1]++ }
  END { for (c in n) printf "%s: CPU mean %.0f%% max %.0f%% (of 200%%), memory max %.0f MiB\n",
        c, sumcpu[c] / n[c], maxcpu[c], maxmem[c] }
' "$work/stats.txt"
