<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Page speed (NF-03)

NF-03 (v1 sheet): "Public topic page shows content in under 1 s on a mid-range phone over
4G." `mix test` cannot check it: it needs a browser on a slowed-down network. It was
measured once, on 2026-11-02, as described below. Measure it again when the topic page, the
stylesheet, the scripts or the fonts change a lot.

## Result

**The topic page shows its content in 0.64 s on 4G with a mid-range phone's CPU**, and its
largest element is drawn at 0.80 s. Both are under 1 s. On slower definitions of "4G" it is
not under 1 s:

| Network profile | Topic page: first content | Topic page: largest content | Home page: first content | Home page: largest content |
| --- | --- | --- | --- | --- |
| **4G**: 70 ms round trip, 9 Mbps (Chrome DevTools' "Fast 4G") | **0.64 s** | **0.80 s** | 0.64 s | 0.78 s |
| 4G with 170 ms round trip, 9 Mbps (WebPageTest's "4G") | 1.54 s | 1.65 s | — | — |
| Lighthouse's default, "Slow 4G": 150 ms round trip, 1.6 Mbps (a 3G-class link) | 1.96 s | 2.63 s | 1.96 s | 2.41 s |

Medians of 3 runs each, which differed by under 0.1 s. In every profile the phone's CPU is
4 times slower than the measuring machine's (Lighthouse's "mid-range phone"), on a 412 px
wide Moto G Power screen. "First content" is First Contentful Paint (the requirement's
"shows content"), "largest content" Largest Contentful Paint. Performance score: 100 on 4G,
95 on Slow 4G. Total blocking time 35 ms (4G) to 61 ms (Slow 4G); layout shift 0.002.

For scale, a page holding only a word and a one-line stylesheet shows in 0.75 s on Slow 4G:
on that profile, a page with any stylesheet starts close to 1 s before anything is drawn.

## What the page costs

The topic is 300 messages long, so the page holds a window of them (see "Long topics" in
CLAUDE.md), and the server answers in about 40 ms. A visitor's first load transfers 245 KB in
27 requests:

| | Compressed size |
| --- | --- |
| The page (HTML) | 9.6 KB |
| Stylesheets (`app.css` 40 KB, the server's `/theme.css` 1 KB) | 41 KB |
| Scripts (`app.js` 62 KB, `theme.js` 0.8 KB) | 63 KB |
| Fonts (two Fraunces and Rubik subsets) | 103 KB |
| Images (emoji, logo, a photo) and icons | 29 KB |

Fonts are loaded with `font-display: swap` and `app.js` with `defer`, so neither holds the
first paint. Three files do, which Lighthouse lists as render-blocking: `app.css`,
`/theme.css` and `theme.js`.

Tried and not kept: putting `theme.js` and `/theme.css` in the page with the request's nonce,
to save their round trips. Slow 4G improved from 1.96 s to 1.66 s, still over 1 s; WebPageTest's
4G did not improve (1.71 s); and it would have broken the "no inline code" rule (SP-05). The
remaining time on slow links is `app.css` and the page itself crossing the network.

## How it was measured

The production build (`MIX_ENV=prod`, digested and compressed assets, `mix phx.server` on
port 4100) on an Intel Core i5-6400 (4 cores), with PostgreSQL in the development container.
Bandit compresses the HTML as Caddy does in production. The data came from
`load/page_speed_seed.exs` on an empty database: an owner, one public category and the
topic "Walks along the river" with 300 messages by 7 people (lists, links, emoji, a photo
every 50th) and some reactions. The page was measured as a visitor, at
`/t/{id}/{slug}`.

Lighthouse 12.2.1 with the Chromium 131 of Microsoft's Playwright image, simulated
throttling (Lighthouse's default), mobile form factor:

```sh
docker run --rm --network host -e CHROME_PATH=/ms-playwright/chromium-1148/chrome-linux/chrome \
  mcr.microsoft.com/playwright:v1.49.1-noble bash -c '
    npm install -g lighthouse@12.2.1 >/dev/null
    F="--chrome-flags=--headless=new --no-sandbox --disable-dev-shm-usage"
    U=http://localhost:4100/t/ID/SLUG
    lighthouse "$U" "$F" --only-categories=performance --output=json --output-path=/tmp/slow4g.json
    lighthouse "$U" "$F" --only-categories=performance --throttling.rttMs=70 \
      --throttling.throughputKbps=9000 --throttling.cpuSlowdownMultiplier=4 \
      --output=json --output-path=/tmp/4g.json'
```

For WebPageTest's 4G, `--throttling.rttMs=170`. The production build also writes digested
copies of every file under `priv/static` (`mix assets.deploy`); remove them afterwards with
`git clean -f priv/static`.
