# Who Was There

Who Was There is a small Elixir service for website analytics. It does not store raw visits. Each hit is reduced to counters, unique estimates, and top lists, then thrown away.

There are no accounts. You create a site with one HTTP request, put a script on your pages, and keep a private dashboard link.

The tracker is about 2 KB and sets no cookies. SQLite keeps only daily aggregates.

**Hosted cloud:** [whowasthere.fyi](https://whowasthere.fyi) — create a site there, no install. **Self-host:** Elixir or Docker on your machine; see [Self-host](#self-host). Do not mix the two: `mix phx.server` serves `http://localhost:4000`, not the public cloud.

## Create a site

On the hosted cloud:

```bash
curl -s https://whowasthere.fyi/new
```

On your own instance, use that origin instead (`http://localhost:4000` in development).

You get something like:

```
whowasthere

site     k4m2xq9p
dash     https://whowasthere.fyi/d/SFMyNTY.…   ← secret; do not put this on the site
snippet  <script src="https://whowasthere.fyi/w.js" data-w="k4m2xq9p.n4m2xq9p.t_….mac" defer></script>
pixel    <img src="https://whowasthere.fyi/w.js?s=k4m2xq9p.n4m2xq9p.t_….mac" alt="" width="1" height="1">
pay      t_…   (trial, until …)
event    window.wwt('signup')
```

JSON if you prefer it:

```bash
curl -sH 'Accept: application/json' https://whowasthere.fyi/new
curl -s 'https://whowasthere.fyi/new?format=json'
```

You can pick the public id, lock the site to a host, attach a paid txid, and leave an email for reminders:

```bash
curl -s 'https://whowasthere.fyi/new?id=my-blog&host=example.com'
curl -s 'https://whowasthere.fyi/new?txid=SOLANA_TXID&email=you@example.com'
```

The public `id` is 8–32 characters (`a-z`, `0-9`, `_`, `-`). It appears in the snippet as the first part of `data-w`. If that id already has a visit, `/new?id=` returns 409.

`/new` signs an ingest key (`id.nonce.payment.mac`) and a dashboard token with the server secret. Without `txid` it opens a **7-day trial**. Looping on `/new` only burns CPU until the first real visit creates the SQLite row. Hits whose `data-w` is missing or forged are ignored.

`host` is optional. If you pass it, it is baked into the ingest key and other origins never count. If you omit it, the first real visit stores the hostname and later hits from other origins are ignored.

The dashboard lives at `/d/…`. That token is signed, not stored, and is not in the snippet: reading your HTML is not enough to open the stats. Save the link. Calling `/new` again with the same id, before any traffic, issues a new token; the previous one still works until a visit claims the id. After that, only the claimed key counts.

## Add the tracker

Put this in `<head>` or before `</body>` (hosted example; on self-host swap in your origin):

```html
<script src="https://whowasthere.fyi/w.js" data-w="SITE_KEY" defer></script>
```

On load it sends a pageview. Client-side route changes (React, Vue, Next, hash routers, Turbo) send another pageview: the tracker wraps `history.pushState` / `replaceState`, listens to `popstate`, `hashchange`, and `navigate`, and also checks the URL every second in case something re-wraps `history`. Clicks use capture on `document` plus `composedPath()`, so nodes added later and Shadow DOM still count. If `sendBeacon` is missing or blocked, it falls back to `fetch` with `keepalive`. Back-forward cache restores (`pageshow`) send a view again. Links, buttons, `[role=button]`, and `[data-wwt]` are tracked (`click:Label`). Set `data-wwt="Buy"` if the visible text is noisy. Heartbeats run while the tab is visible. On leave it sends a close signal. It does not set cookies.

Events POST back to the same `/w.js` URL the script was loaded from. There is no `/collect`, no pixel filename, and no `analytics` in the path. Lists that block third-party scripts by hostname will still win if the file is served from a known tracker domain; the usual fix is to proxy `/w.js` on your own site and point the snippet at that origin:

```
location /w.js {
  proxy_pass http://127.0.0.1:4000/w.js;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}
```

Then the snippet is just `<script src="/w.js" data-w="SITE_KEY" defer></script>`. Ad blockers treat it as first-party. Country headers from your CDN still apply if the proxy forwards them.

UTM `source`, `medium`, and `campaign` come from the landing query. The first non-empty values stay on the session, so a SPA that strips the query still attributes later pages to that campaign. Viewport width is stored in four buckets (`0-639`, `640-1023`, `1024-1439`, `1440+`), not the raw pixel count.

Without JavaScript you can count pageviews only:

```html
<img src="https://whowasthere.fyi/w.js?s=SITE_KEY" alt="" width="1" height="1">
```

Custom events (they do not increment pageviews):

```js
wwt('signup')
wwt('buy')
```

Names are trimmed to 40 characters.

## Dashboard

Open the secret URL from `/new`: `https://whowasthere.fyi/d/TOKEN`.

The public id does not work as a dashboard path. The page updates live. You can switch between today, 7, 30, and 90 days.

| Metric | Meaning |
| --- | --- |
| Pageviews | `v` hits |
| Uniques | HyperLogLog, about 1.6% error. For one day this is the HLL estimate. For a range it is the **sum of daily** uniques |
| Sessions | a gap longer than 30 minutes starts a new session |
| Bounce rate | sessions with at most one pageview |
| Avg. time | total duration / sessions |
| Live | sessions active in the last 5 minutes |
| Journeys | one sequence per session including clicks, up to 8 steps |
| Steps | page `A → B` |
| Clicks | link/button/`data-wwt` clicks |
| Landings / exits | first and last page of a session |
| Pages / referrers / UTM / geo / devices / events | top 20, at most 150 keys per kind |

Country comes from a CDN header (`CF-IPCountry`, `CloudFront-Viewer-Country`, `x-vercel-ip-country`, `x-country-code`). If those are missing, the language tag is used (`ru-RU` → `RU`).

## What is not stored

IP addresses, User-Agent strings, cookies, and individual hits never hit disk.

Uniques use a salt that rotates every UTC day, so the same person is not linked across days. A session lives in ETS for 30 minutes and keeps a short chain of pages and clicks (at most 8 steps). The dashboard shows the current chain while the session is open; when it expires, that finished sequence is counted once and the last page is an exit. Intermediate prefixes are not stored. Individual visit trails are not stored.

SQLite holds `sites`, `days`, `dims`, and `hours` — aggregates only, typically kilobytes per site per day. Today's HyperLogLog sketch (~4 KB) is kept so a restart does not reset uniques; older days keep only the number.

## Domain lock

The first visit (or `?host=` on `/new`) stores the hostname without `www.`. Later events from another origin are ignored. The collector still responds 204.

## Pricing

**$30 USDC / year** on Solana. One payment covers unlimited sites and a shared **500 000 pageviews / month**. Without payment you get a **7-day trial**; after that (or when the year ends) hits are dropped until you renew. Same price on the hosted cloud and on a self-hosted copy (you receive the USDC if you set `PAY_WALLET`).

```bash
curl -s https://whowasthere.fyi/pay
# send 30 USDC to the wallet shown, then:
curl -s 'https://whowasthere.fyi/new?txid=YOUR_TXID&email=you@example.com'
# or move every site from an old payment onto a new tx:
curl -s 'https://whowasthere.fyi/renew?from=OLD_PAY_OR_TXID&to=NEW_TXID&email=you@example.com'
```

Email is optional. If you set one (`/new?email=`, `/renew?email=`, or `/notify?pay=&email=`), you get mail when the trial or year is about to end, when it has expired, and at ~80% / 100% of the monthly pageview cap. Delivery uses Resend when `RESEND_API_KEY` is set.

## API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/new` | create a site (7-day trial) |
| `GET` | `/new?id=&host=&txid=&email=&format=json` | same, with options |
| `GET` | `/pay` | wallet, price, example curls |
| `GET` | `/renew?from=&to=&email=` | reattach all sites to a new paid year |
| `GET` | `/notify?pay=&email=` | set reminder email |
| `GET` | `/w.js` | tracker |
| `POST` | `/w.js` | event (`text/plain` JSON) |
| `GET` | `/w.js?s=` | 1×1 gif pageview |
| `GET` | `/d/:token` | private dashboard |
| `GET` | `/health` | `{ "ok": true }` |

`POST /w.js` allows CORS `*` and skips CSRF. `sendBeacon` with `text/plain` does not trigger a preflight. `/t.js`, `/e`, and `/e.gif` still work as aliases.

```json
{
  "s": "SITE_KEY",
  "n": "v",
  "p": "/pricing",
  "q": "?utm_source=twitter&utm_medium=social&utm_campaign=launch",
  "h": "example.com",
  "r": "https://t.co/x",
  "l": "ru-RU",
  "w": 1280,
  "e": "signup"
}
```

| Field | Meaning |
| --- | --- |
| `s` / `site` | ingest key from `/new` (`id.nonce.payment.mac`) |
| `n` / `name` | `v` pageview, `h` heartbeat, `x` leave, `k` click, `c` custom event |
| `p` / `path` | path without query |
| `q` / `query` | query string; `utm_source` / `source` / `ref`, `utm_medium`, `utm_campaign`. The first non-empty values in a session stick for later SPA views that drop the query |
| `h` / `host` | page host, if `Origin` / `Referer` are missing |
| `r` / `ref` | referrer |
| `l` / `lang` | `navigator.language` |
| `w` / `width` | `innerWidth`; stored as `0-639`, `640-1023`, `1024-1439`, or `1440+` |
| `e` / `event` | custom event name |

Smoke test (expect `204`). Known bots (`curl`, `wget`, crawlers, headless browsers) are ignored:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'User-Agent: Mozilla/5.0 Chrome/120.0.0.0' \
  -H 'Origin: https://example.com' \
  -H 'Content-Type: text/plain' \
  -d '{"s":"KEY_FROM_NEW","n":"v","p":"/hello"}' \
  https://whowasthere.fyi/w.js
```

## Self-host

This section is only for running **your own** copy. It talks to `localhost` (or whatever origin you bind). The hosted cloud is [whowasthere.fyi](https://whowasthere.fyi); `mix phx.server` does not start that site.

You need Elixir 1.17 or newer (1.20 / OTP 29 is what we test on). Mix is enough; SQLite is embedded.

```bash
mix setup
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000). Create a site with `curl -s http://localhost:4000/new` — that key and dashboard belong to your process, not to the public cloud.

```bash
mix test          # tests
mix ecto.reset    # wipe and recreate the database
```

In development the database file is `config/whowasthere_dev.db`.

### Production

| Variable | Purpose |
| --- | --- |
| `PHX_SERVER=true` | start HTTP in a release |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` |
| `DATABASE_PATH` | SQLite file, e.g. `/data/whowasthere.db` |
| `PHX_HOST` | public hostname |
| `PORT` | listen port, default `4000` |
| `POOL_SIZE` | SQLite pool, default `5` |
| `PAY_WALLET` | Solana address that receives USDC |
| `SOLANA_RPC` | optional RPC URL (default public mainnet) |
| `RESEND_API_KEY` | optional; enables expiry / quota emails via Resend |

```bash
docker build -t whowasthere .
docker run --rm -p 4000:4000 \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e PHX_HOST=localhost \
  -v wwt-data:/data \
  whowasthere
```

Or use the included `compose.yml`. Behind TLS, send `X-Forwarded-Proto`. `/health` is excluded from the HTTPS redirect. Releases run migrations on boot.

## License

GNU Affero General Public License v3.0. See [LICENSE](LICENSE).

## Internals

1. `POST /w.js` verifies the signed ingest key, parses the user agent, takes country from a header, and does **not** persist the hit. The site row is created on that first verified visit.
2. `WhoWasThere.Collector` keeps today's counters, HyperLogLog, tops, and sessions in ETS.
3. Dirty sites flush to SQLite every 15 seconds (5 seconds in dev).
4. The dashboard reads today from ETS and older days from SQLite.

Stack: Phoenix 1.8, LiveView, Bandit, SQLite.
