# Who Was There

Who Was There is a small Elixir service for website analytics. It does not store raw visits. Each hit is reduced to counters, unique estimates, and ranked breakdowns, then discarded.

There are no accounts. Creating a site gives you two private links instead of a login: a dashboard URL for stats and a payment URL for billing. Treat both like passwords: if you lose them, you lose access.

The tracker is about 2 KB and sets no cookies. SQLite keeps only daily aggregates.

**Hosted service:** [whowasthere.fyi](https://whowasthere.fyi). **Run your own instance:** [Self-host](#self-host).

## Create a site

Use the origin of the instance that will collect your data. The hosted service uses:

```bash
curl -s https://whowasthere.fyi/new
```

On a self-hosted instance, use its public origin instead (`http://localhost:4000` in development).

You get something like:

```
whowasthere

site     k4m2xq9p
dash     https://whowasthere.fyi/d/SFMyNTY.…   ← secret; do not put this on the site
snippet  <script src="https://whowasthere.fyi/w.js" data-w="k4m2xq9p.n4m2xq9p.t_….mac" defer></script>
pixel    <img src="https://whowasthere.fyi/w.js?s=k4m2xq9p.n4m2xq9p.t_….mac" alt="" width="1" height="1">
pay      p_…   ← secret payment profile; keep it with the dashboard URL
pay URL  https://whowasthere.fyi/pay?pay=p_…
deposit  8x…   (USDC on Solana)
event    window.wwt('signup')
```

JSON if you prefer it:

```bash
curl -sH 'Accept: application/json' https://whowasthere.fyi/new
curl -s 'https://whowasthere.fyi/new?format=json'
```

You can choose the public ID, lock the site to a host, reuse a private payment profile, and add an email address for reminders:

```bash
curl -s 'https://whowasthere.fyi/new?id=my-blog&host=example.com'
curl -s 'https://whowasthere.fyi/new?pay=p_SECRET&email=you@example.com'
```

The public `id` is 8–32 characters (`a-z`, `0-9`, `_`, `-`). It appears in the snippet as the first part of `data-w`. If that ID has already received a visit, `/new?id=` returns 409.

`/new` signs an ingest key (`id.nonce.payment.mac`) and a dashboard token with the server secret. If `pay` is omitted, it issues a private payment capability. The **7-day free trial** starts when the profile first receives a hit or is accessed through `/pay` or `/notify`. Until then, the capability is not written to the database, so unused `/new` requests do not fill SQLite. Supplying `email=` stores the profile immediately so reminders can be scheduled. Save both secret URLs from the response; every call without `pay` issues a new capability. Hits with a missing or forged `data-w` value are ignored.

`host` is optional. If you supply it, the hostname is embedded in the ingest key and traffic from other origins is ignored. If you omit it, the first real visit sets the hostname; later traffic from other origins is ignored.

The dashboard lives at `/d/…`. Its token is signed, not stored, and never appears in the tracker snippet, so reading your HTML is not enough to open the dashboard. Save the link. Calling `/new` again with the same ID before any traffic issues a new token. The previous token remains valid until the first visit claims the ID; after that, only the claimed ingest key is accepted.

## Add the tracker

Put this in `<head>` or before `</body>`. The script URL must use the same instance origin as `/new`:

```html
<script src="https://whowasthere.fyi/w.js" data-w="SITE_KEY" defer></script>
```

On load, it sends a pageview. Client-side route changes (React, Vue, Next, hash routers, Turbo) send another pageview: the tracker wraps `history.pushState` / `replaceState`, listens to `popstate`, `hashchange`, and `navigate`, and also checks the URL every second in case something re-wraps `history`. Clicks use capture on `document` plus `composedPath()`, so nodes added later and elements in Shadow DOM still count. If `sendBeacon` is missing or blocked, the tracker falls back to `fetch` with `keepalive`. Back-forward cache restores (`pageshow`) send another view. Links, buttons, `[role=button]`, and `[data-wwt]` are tracked (`click:Label`). Set `data-wwt="Buy"` if the visible text is noisy. Heartbeats run while the tab is visible. When the visitor leaves, the tracker sends a close signal. It does not set cookies.

Events are sent with `POST` to the same `/w.js` URL that loaded the script. There is no `/collect`, no pixel filename, and no `analytics` in the path. Ad blockers can still block the script when it is served from a known tracker domain. To serve it as a first-party resource, proxy `/w.js` through your own site and point the snippet at that origin:

```
location /w.js {
  proxy_pass http://127.0.0.1:4000/w.js;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}
```

Then the snippet is just `<script src="/w.js" data-w="SITE_KEY" defer></script>`. Ad blockers treat it as first-party. Country headers from your CDN still apply if the proxy forwards them.

UTM `source`, `medium`, and `campaign` come from the landing query. The first non-empty values persist for the session, so an SPA that strips the query still attributes later pages to that campaign. Viewport width is stored in four buckets (`0-639`, `640-1023`, `1024-1439`, `1440+`), not as a raw pixel count.

Without JavaScript, you can track pageviews only:

```html
<img src="https://whowasthere.fyi/w.js?s=SITE_KEY" alt="" width="1" height="1">
```

Custom events do not increment pageviews:

```js
wwt('signup')
wwt('buy')
```

Names are trimmed to 40 characters.

## Dashboard

Open the secret URL returned by `/new`, for example: `https://whowasthere.fyi/d/TOKEN`.

The public ID is not a dashboard URL. The page updates live. You can switch between today and the last 7, 30, or 90 days.

| Metric | Meaning |
| --- | --- |
| Pageviews | `v` hits |
| Unique visitors | HyperLogLog, about 1.6% error. For a single day, this is the HLL estimate. For a range, it is the **sum of daily** estimates |
| Sessions | a gap longer than 30 minutes starts a new session |
| Bounce rate | sessions with at most one pageview |
| Avg. time | total duration / sessions |
| Live | sessions active in the last 5 minutes |
| Session paths | one sequence per session, including clicks, up to 8 steps |
| Page transitions | consecutive pages, such as `A → B` |
| Clicks | clicks on links, buttons, and elements with `data-wwt` |
| Landings / exits | first and last page of a session |
| Pages / referrers / UTM / geo / devices / events | top 20, at most 150 keys per kind |

Country comes from a CDN header (`CF-IPCountry`, `CloudFront-Viewer-Country`, `x-vercel-ip-country`, `x-country-code`). If those are missing, the language tag is used (`ru-RU` → `RU`).

## What is not stored

IP addresses, User-Agent strings, cookies, and individual hits are never written to disk.

Uniques use a salt that rotates every UTC day, so the same person is not linked across days. A session lives in ETS for 30 minutes and keeps a short chain of pages and clicks (at most 8 steps). The dashboard shows the current chain while the session is open; when it expires, that finished sequence is counted once and the last page is an exit. Intermediate prefixes are not stored. Individual visit trails are not stored.

SQLite holds `sites`, `days`, `dims`, and `hours` — aggregates only, typically kilobytes per site per day. Today’s HyperLogLog sketch (~4 KB) is kept so a restart does not reset the estimate; older days retain only the estimated count.

## Domain lock

The first visit (or `?host=` on `/new`) stores the hostname without `www.`. Later events from another origin are ignored. The collector still returns a `204` response.

## Payment details

**$30 a year** — by card (Stripe, when configured) or with USDC on Solana. One payment link covers unlimited sites with a shared limit of **500,000 pageviews per month**. Pay more at once and the monthly limit grows by **500,000 for every additional $30** ($60 → 1,000,000, $90 → 1,500,000). You get a **7-day free trial**; when the trial or paid year ends, new pageviews are discarded until you renew.

The first `/new` response includes a private `pay URL` field and a permanent Solana deposit address. Open that URL in a browser for a dedicated payment page with the current plan status, amount controls, card payment, wallet link, and QR code.

**Card:** open the payment link in a browser (or stay on the homepage after creating a site), choose the amount, and click **Pay by card**. Stripe Checkout charges the card in USD and activates the plan after the webhook confirms the payment.

**Solana:** send USDC to the deposit address, then click **Check USDC payment** in the browser or call `/pay?pay=p_SECRET` from an API client. The instance sweeps confirmed USDC into `PAY_WALLET`. Blockchain transaction IDs are never credentials.

```bash
curl -s https://whowasthere.fyi/new
# check the payment status or settle a confirmed USDC transfer:
curl -s 'https://whowasthere.fyi/pay?pay=p_SECRET'
# every later site can share that profile:
curl -s 'https://whowasthere.fyi/new?pay=p_SECRET&email=you@example.com'
```

### Renew

Use the same payment link for the first year and every renewal.

**Card:** open the saved payment URL in a browser, choose $30 or more, and click **Pay by card**. Each successful checkout adds another year from the current expiration date, or from today if the plan has expired. It also raises the monthly limit in the same way as a USDC payment.

**Solana:** send another 30 USDC to the same deposit address, then check the payment:

```bash
curl -s 'https://whowasthere.fyi/renew?pay=p_SECRET'
# /pay is identical:
curl -s 'https://whowasthere.fyi/pay?pay=p_SECRET'
```

After settlement, one year is added to the plan. Calling either endpoint when the deposit address is empty only returns the current status; it cannot extend the plan twice. Every settled $30 gives the profile 500,000 monthly pageviews.

There is no background blockchain watcher and no transaction ID to submit. Opening `/pay`, `/renew`, or `/new?pay=p_SECRET` checks and settles the Solana address. Card renewals are confirmed through Stripe webhooks.

Email is optional. If you add an address (`/new?email=` or `/notify?pay=p_SECRET&email=`), you receive a message when the trial or paid year is about to end, when it expires, and when usage reaches about 80% or 100% of the monthly pageview limit. Delivery uses your Postal server when `POSTAL_URL` and `POSTAL_API_KEY` are set, or Resend when `RESEND_API_KEY` is set. Postal takes precedence when both are configured.

## API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/new` | create a site (7-day trial) |
| `GET` | `/new?id=&host=&pay=&email=&format=json` | same, optionally using a private payment profile |
| `GET` | `/pay?pay=p_SECRET` | open payment options in a browser; check and settle Solana deposits through the API |
| `POST` | `/pay/checkout` | start Stripe Checkout (`pay`, `amount`; browser CSRF) |
| `POST` | `/stripe/webhook` | Stripe webhooks (signature required) |
| `GET` | `/renew?pay=p_SECRET` | alias for `/pay` |
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
| `q` / `query` | query string; `utm_source` / `source` / `ref`, `utm_medium`, `utm_campaign`. The first non-empty values are preserved for later SPA views that drop the query |
| `h` / `host` | page host, if `Origin` / `Referer` are missing |
| `r` / `ref` | referrer |
| `l` / `lang` | `navigator.language` |
| `w` / `width` | `innerWidth`; stored as `0-639`, `640-1023`, `1024-1439`, or `1440+` |
| `e` / `event` | custom event name |

Smoke test (expect a `204` response). Known bots (`curl`, `wget`, crawlers, headless browsers) are ignored:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'User-Agent: Mozilla/5.0 Chrome/120.0.0.0' \
  -H 'Origin: https://example.com' \
  -H 'Content-Type: text/plain' \
  -d '{"s":"KEY_FROM_NEW","n":"v","p":"/hello"}' \
  https://whowasthere.fyi/w.js
```

## Self-host

You need Elixir 1.17 or newer; we test with Elixir 1.20 and OTP 29. SQLite is embedded, so no external database is required. A self-hosted operator can grant private profiles for their own sites directly from the server console. Blockchain payment configuration is only needed when the instance accepts payments from other people.

```bash
mix setup
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000).

```bash
curl -s http://localhost:4000/new
mix test
mix ecto.reset
```

In development, the database file is `config/whowasthere_dev.db`.
The development environment issues deterministic demo deposit addresses and never settles them. Do not send funds to those addresses.

### Free profiles for your own sites

Create the first site on your instance and save the returned `p_SECRET`:

```bash
curl -s 'https://analytics.example.com/new?format=json'
```

Grant that private payment profile locally. From the source tree:

```bash
mix run -e 'IO.inspect(WhoWasThere.Billing.grant("p_SECRET", years: 10))'
```

From a production release:

```bash
bin/whowasthere eval 'IO.inspect(WhoWasThere.Billing.grant("p_SECRET", years: 10))'
```

For a release running in Docker, execute the same command inside its container:

```bash
docker exec CONTAINER bin/whowasthere eval \
  'IO.inspect(WhoWasThere.Billing.grant("p_SECRET", years: 10))'
```

The profile is stored as `comp`. Use its existing secret for every site that should share the grant:

```bash
curl -s 'https://analytics.example.com/new?pay=p_SECRET'
```

The default shared allowance is 500,000 pageviews per month. Set another limit explicitly when needed:

```bash
bin/whowasthere eval \
  'IO.inspect(WhoWasThere.Billing.grant("p_SECRET", years: 10, month_cap: 2000000))'
```

Running `grant` again extends an active `comp` profile from its current expiry. `PAY_MASTER_KEY` is still required in production because it derives each profile's stable deposit address; keep it unchanged and backed up. `PAY_WALLET`, a funded fee-payer address, and Solana RPC access are unnecessary when the instance only uses local grants.

### Production

| Variable | Purpose |
| --- | --- |
| `PHX_SERVER=true` | start HTTP in a release |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` |
| `DATABASE_PATH` | SQLite file, e.g. `/data/whowasthere.db` |
| `PHX_HOST` | public hostname |
| `PORT` | listen port, default `4000` |
| `POOL_SIZE` | SQLite pool, default `5` |
| `PAY_MASTER_KEY` | required; base58-encoded 32-byte Ed25519 seed for stable payment-profile addresses |
| `PAY_WALLET` | required for paid Solana profiles; treasury owner whose existing USDC token account receives sweeps |
| `SOLANA_RPC` | used for paid Solana profiles; optional RPC URL (defaults to Solana’s public mainnet endpoint) |
| `STRIPE_SECRET_KEY` | optional; enables Stripe Checkout (`sk_…` or restricted key) |
| `STRIPE_WEBHOOK_SECRET` | optional with Stripe; webhook signing secret (`whsec_…`) for `/stripe/webhook` |
| `MAIL_FROM` | sender address; its domain must be authorized by the selected mail provider |
| `POSTAL_URL` | optional; base URL of a Postal server, e.g. `https://postal.example.com` |
| `POSTAL_API_KEY` | Postal server API credential; set together with `POSTAL_URL` |
| `RESEND_API_KEY` | optional Resend fallback when Postal is not configured |

```bash
docker build -t whowasthere .
docker run --rm -p 4000:4000 \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e PAY_MASTER_KEY=BASE58_32_BYTE_SEED \
  -e PHX_HOST=localhost \
  -v wwt-data:/data \
  whowasthere
```

Or use the included `compose.yml`. Behind a TLS-terminating proxy, forward `X-Forwarded-Proto`. `/health` is excluded from the HTTPS redirect. Releases run migrations on boot.

For Postal, create a server API credential in its web interface and set:

```bash
MAIL_FROM='Who Was There <noreply@example.com>'
POSTAL_URL='https://postal.example.com'
POSTAL_API_KEY='...'
```

Generate `PAY_MASTER_KEY` once as a base58-encoded 32-byte seed and back it up. Keep a small SOL balance at the fee-payer address derived from it to cover sweep fees. The production deployment workflow generates the key in the correct format when it is absent. `PAY_WALLET` can remain a separate treasury whose private key is kept offline. To print the fee-payer address from a configured release:

```bash
bin/whowasthere eval 'IO.inspect(WhoWasThere.Billing.Solana.master_address())'
```

On the first USDC transfer, the payer’s wallet creates an associated token account for the derived owner address. There is no background blockchain watcher: `/pay?pay=p_SECRET` and `/new?pay=p_SECRET` query that address, sweep its confirmed USDC balance, wait for confirmation, and only then update the plan. Public transaction IDs are never accepted as proof of payment.

## License

GNU Affero General Public License v3.0. See [LICENSE](LICENSE).

## Internals

1. `POST /w.js` verifies the signed ingest key, parses the user agent, gets the country from a header, and does **not** persist the hit. The site row is created on that first verified visit.
2. `WhoWasThere.Collector` keeps today’s counters, HyperLogLog sketch, ranked dimensions, and sessions in ETS.
3. Dirty sites flush to SQLite every 15 seconds (5 seconds in dev).
4. The dashboard reads today from ETS and older days from SQLite.

Stack: Phoenix 1.8, LiveView, Bandit, SQLite.

Article (RU): https://www.bythe.net/p/kto-zdes-byl-veb-analitika-na-elixir-bez-akkauntov-i-zhurnala-posescheniy
