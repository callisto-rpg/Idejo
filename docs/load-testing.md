# Load testing

Idejo promises live delivery within 200 ms (NF-01, 95th percentile) for about 200 people
online on the minimum server: 2 vCPU, 2 GB RAM (NF-04). The v1 sheet asks for a load test
before each release (NF-10); this is it.

## Running it

From the repository root, on a machine with Docker, Elixir (`mise install`) and 4 CPUs or
more:

```sh
load/run.sh                      # 200 people in 10 topics, 30 of them writing, 3 minutes
load/run.sh --hot --writers 10   # all 200 in one topic, 10 writing
```

`load/run.sh` builds the production image, starts the app and PostgreSQL with
`load/docker-compose.load.yml`, both pinned to CPUs 0 and 1 and given 1.5 GB and 0.5 GB of
memory: the minimum server, shared as on a real one. It seeds 200 verified people and 10
topics (`load/seed.exs`), runs the generator (`load/run.exs`) on the other CPUs, samples
the containers' CPU and memory, and removes everything afterwards, volumes included. The app
is reached directly on `localhost:4100`, without Caddy.

The generator does what browsers do:
- every person signs in through the sign-in form, from an address of their own (sent in
  `X-Forwarded-For`, as Caddy does, so the per-address rate limits count each person);
- each loads their topic's page and joins its LiveView over a websocket;
- the writers press Enter every 2 to 4 seconds, as in a chat, sending the composer's
  `commit` event the way `assets/js/composer.js` does (what was sent, then the new words and a
  full stop, so the server sees appends, not edits); every 15th Enter is Ctrl+Enter;
- meanwhile about 5 public pages a second are loaded by other visitors.

Every commit carries a marker. **Live latency** is the time from sending the commit to each
other viewer of the topic receiving the update with that marker. It also reports the
writer's round trip, page load times, and the containers' CPU and memory.

`load/top.exs` shows where the server spends its time during a run (run it with
`bin/idejo rpc 'Code.eval_file("/load/top.exs")'` in the app container).

## Results

Measured on 2026-10-22, 4-core machine (app and database on 2 of them), 3 minutes each after
a 10 s warm-up, with the fixes below.

| | 200 people, 10 topics, 30 writing | 200 people in one topic, 10 writing |
| --- | --- | --- |
| Enters | 1,797 (10 a second) | 595 (3.3 a second) |
| Updates delivered to other viewers | 34,143 of 34,143 | 118,405 of 118,405 |
| **Live latency (NF-01)** | **p50 23 ms · p95 40 ms** · p99 58 ms · max 85 ms | **p50 73 ms · p95 145 ms** · p99 206 ms · max 308 ms |
| Writer's round trip | p95 36 ms, no errors | p95 112 ms, no errors |
| Public pages (5 a second) | p95 30 ms, none failed | p95 73 ms, none failed |
| App CPU (of 200%) | mean 56% | mean 69% |
| App memory, at most | 355 MiB of 1.5 GB | 474 MiB of 1.5 GB |
| Database CPU / memory | mean 10% / 93 MiB | mean 8% / 92 MiB |
| Restarts, out-of-memory kills | none | none |

The CPU peaks (198–199%) are the 200 sign-ins at the start, each hashing a password with
Argon2id (SP-02), not the conversation.

Both meet NF-01 on the NF-04 server, with room to spare in the usual case (people spread over
topics). The worst realistic case, one topic everybody watches with 10 people writing, is
within the target at p95; its p99 is just over it.

## What the test found

- **Rate limits counted every visitor as Caddy** (SP-05, fixed in #78). Behind Caddy,
  Bandit sees its address as IPv4-mapped IPv6 (`::ffff:172.x.y.z`), which the client-address
  plug did not recognise as the proxy, so 10 sign-ins and 300 requests a minute were shared
  by everybody. These results were measured with that fix.
- **Each viewer queried the database for every update** (fixed here). Every topic view
  loaded the message's author, versions and reply again, and looked up authors' roles even
  when it knew them all: six or more queries per viewer per Enter. With 200 people in one
  topic the pool ran dry, views crashed and reconnected, and the latency reached seconds.
  The message is now loaded once when it is broadcast, and roles only for new authors. The
  hot topic with 10 writers went from p95 554 ms to 145 ms.

## Limits

One topic where 30 people write at once while 200 watch (10 Enters a second, about 2,000
view updates a second) is past what 2 vCPU can render: p50 142 ms but p95 2.1 s, and some
views dropped when the database pool timed out. The time goes to rendering the topic's
message list in every view (LiveView's keyed list and the JSON of each change), not to the
database. Rendering the list as a LiveView stream would cut that cost; it is a larger change
to the topic page, for a later release.

## Idle memory (NF-12)

An idle instance, with no one online, should use under 200 MB of memory, so that several can
share a host (NF-12, M6). It is measured, not enforced.

### Method

On the production image (`docker build .`, the release as the bundle runs it), with
`deploy/docker-compose.yml` and `deploy/docker-compose.external-proxy.yml` (app and
PostgreSQL, no Caddy):

1. start the app and wait until it is healthy, then set it up with
   `bin/idejo-admin setup --name "Idle Club" --owner-email …`;
2. for the **warmed** runs, load what visitors load once: the home page, sign-in, sign-up,
   help, rules, search, privacy, a category, a topic page (its LiveView rendered on the
   server), the manifest, the stylesheet, the emoji index, the sitemap, and a failed sign-in.
   (A signed-in session was not reached: curl, over plain http, does not send the `Secure`
   session cookie back.)
3. leave it alone for **5 minutes** (only its own health check every 15 s);
4. take **10 readings 30 s apart** with `docker stats --no-stream` (the container's memory:
   its cgroup's usage less inactive file cache), then `:erlang.memory()` through
   `bin/idejo rpc`, and the cgroup's `memory.stat`.

Machine: Intel Core i5-6400 (4 cores), 7.2 GiB RAM, Linux 7.0, Docker 29.9.2 (cgroup v2),
Erlang/OTP 29.1.2, Elixir 1.20.4; the image built from main at `cf55ad1` (2026-11-02). The
VM runs 4 schedulers (one per core) and the default `POOL_SIZE` of 10.

### Results (2026-11-02)

| Run | App container (`docker stats`, 10 readings) | VM (`:erlang.memory`): total · code · processes | PostgreSQL |
| --- | --- | --- | --- |
| Default release, just set up | **202.7–204.1 MiB** (≈ 214 MB) | 129 MiB · 64 MiB · 23 MiB | 62 MiB |
| Default release, warmed | **226.0–227.1 MiB** (≈ 238 MB) | 129 MiB · 64 MiB · 23 MiB | 73 MiB |
| `RELEASE_MODE=interactive`, just set up | 62.5–63.4 MiB (≈ 66 MB) | 59 MiB · 19 MiB · 19 MiB | 52 MiB |
| `RELEASE_MODE=interactive`, warmed | **98.5–98.7 MiB** (≈ 103 MB) | 67 MiB · 23 MiB · 19 MiB | 84 MiB |

Each run was flat over its five minutes (a spread under 1 MiB): nothing grows while idle.

**As released today, an idle instance is over the target: about 204 MiB (214 MB), 227 MiB
(238 MB) once pages have been served.** With `RELEASE_MODE=interactive` it is well under it.

### Where it goes (default release, warmed)

- **Loaded code, 64 MiB, and its JIT-compiled native code, about 50 MiB** (the cgroup's
  `shmem`: the JIT maps its code twice, through shared memory). A release starts in
  *embedded* mode and loads every module of the app and all its dependencies at boot, used or
  not (the admin panel, image processing, push encryption, OpenID Connect, backups, Swoosh's
  adapters, the dev-time LiveDashboard plug's modules…).
- **Processes, 23 MiB**, 579 of them: the database pool, Oban's queues and plugins, PubSub,
  the endpoint's acceptors, per-scheduler allocator carriers.
- **The rest of the VM**: ETS 5 MiB, binaries 4 MiB, atoms 2 MiB, and the allocators' unused
  carrier space (the cgroup's anonymous memory, 163 MiB, is more than the VM's 129 MiB).
- The **page cache** of the release's files (84 MiB) is mostly not counted (inactive) and the
  kernel takes it back under pressure.

### Cheapest reductions (not applied: a steward decision)

1. **`RELEASE_MODE=interactive`** (measured above): modules load the first time they are
   used instead of all at boot. Warmed, **227 → 99 MiB**. One line (`ENV
   RELEASE_MODE=interactive` in the Dockerfile's runtime stage, or in a new `rel/env.sh.eex`). Costs: the first use of each module takes a few milliseconds more (a
   page's first visit after a restart), and memory grows towards the embedded figure as more
   features are used: an instance whose members use everything ends between the two.
2. **`POOL_SIZE`**: 10 database connections per instance (each also a PostgreSQL backend,
   several MiB on the database side). 5 is plenty for an idle or small forum. Not measured.
3. **Schedulers**: the VM starts one scheduler per core of the host, each with its own
   allocator carriers; on a shared host with many instances, `+S 2:2` (in a new `rel/vm.args.eex`)
   would cap that. Not measured.
4. **Fewer modules in the release**: `Phoenix.LiveDashboard.RequestLogger` is plugged in
   every environment though the dashboard is development-only. Small; only worth it with
   embedded mode.

Reproduce: the scripts that took these readings are not in the repository; the steps above
are all they do. `deploy/test/m6/run.sh` starts the same layout for two instances.
