# Cap Standalone on Railway — one-click, proof-of-work CAPTCHA

Deploy [Cap standalone](https://trycap.dev/guide/standalone/) — the privacy-first,
proof-of-work CAPTCHA alternative to reCAPTCHA — to Railway in one click. No Google,
no tracking, no per-request fees.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new?github_url=https://github.com/ikasima0/cap-standalone-railway)

> Replace the button URL with the short `https://railway.com/deploy/<code>` form once
> the template is published.

## What gets deployed

| Service | Image | Purpose |
|---|---|---|
| `cap` | `tiago2/cap:3.1.11` (pinned) | Cap standalone server + dashboard, port 3000, public TCP proxy |
| `valkey` | `valkey/valkey:9-alpine` | Redis-compatible challenge/token store, private network only, `/data` volume |

Two environment variables, both auto-provisioned — nothing to fill in:

- `ADMIN_KEY` — randomly generated 32+ char secret (Railway's secret generator); log into the dashboard with it.
- `REDIS_URL` — `redis://valkey.railway.internal:6379`, wired over Railway's private network.

### Persistence

Challenge state lives in Valkey. A 500 MB volume is mounted at `/data` so in-flight
challenges, site keys, and rate-limit counters survive restarts and redeploys — this is
the setup the [official docs](https://trycap.dev/guide/standalone/) recommend. Without
it, every deploy invalidates all site keys and tokens.

## 60-second self-check after deploy

1. Open the public domain of the `cap` service — the dashboard loads.
2. Log in with `ADMIN_KEY` (Railway → `cap` service → Variables).
3. Create a site key. Note the **site key** (public) and **secret key** (private).
4. Open `https://<your-domain>/demo?site_key=<site_key>` — this repo serves a demo page
   from the template docs (see below), or use any page with the widget:

   ```html
   <script src="https://cdn.jsdelivr.net/npm/cap-widget@latest"></script>
   <cap-widget data-cap-api-endpoint="https://<your-domain>/<site-key>/"></cap-widget>
   ```

5. Solve the puzzle, then verify the token server-side:

   ```bash
   curl -X POST https://<your-domain>/<site-key>/siteverify \
     -H 'Content-Type: application/json' \
     -d '{"secret": "<secret_key>", "response": "<token>"}'
   # → {"success": true}
   ```

The token comes from the widget's `solve` event (`e.detail.token`) or the hidden
`cap-token` form field. Tokens are single-use. **Use the secret key here, not the
ADMIN_KEY** — mixing them up is the most common setup mistake.

### Demo page

[`demo/index.html`](demo/index.html) is a self-contained page that loads the Cap widget,
solves against your instance, shows the token, and verifies it via `siteverify` — copy it
anywhere (it must be served from a public origin, not `localhost`, since Cap's widget
requires a reachable API endpoint). To use the demo hosted by your instance, deploy it as
any static site pointing `data-cap-api-endpoint` at your Railway domain.

## Configuration

Everything else is optional — see the [official options](https://trycap.dev/guide/standalone/options.html):

| Variable | Default | Purpose |
|---|---|---|
| `CORS_ORIGIN` | `*` | Comma-separated allowed origins for challenge redeem |
| `ENABLE_ASSETS_SERVER` | `false` | Serve widget/WASM files from `/assets` on your instance |
| `WIDGET_VERSION` / `WASM_VERSION` | `latest` | Pin npm versions of `@cap.js/widget` / `@cap.js/wasm` |
| `REDIS_PREFIX` | *(empty)* | Namespace keys when sharing a Valkey instance |

## Troubleshooting

- **Widget never loads / CORS errors on a custom domain** — set `CORS_ORIGIN` to your
  site's origin(s), comma-separated. The default `*` works on Railway domains.
- **Dashboard login rejected** — you're using a site secret key; the dashboard wants
  `ADMIN_KEY` (service variable, auto-generated).
- **`siteverify` returns 404** — the path is `/<site-key>/siteverify`; the site key is in
  the URL.
- **Custom domain** — generate a domain on the `cap` service; only that service needs to
  be public. Valkey stays private.

## Local development

`docker-compose.yml` mirrors the Railway setup (Cap on `localhost:3000`, Valkey with a
data volume): `docker compose up`.

## Cost

Both services idle at well under 512 MB RAM combined; expect roughly **$3–5/month** on
Railway's usage pricing.

---

# Deploy and Host

## About Hosting

Hosting Cap standalone on Railway runs two small containers: the `cap` server
(`tiago2/cap:3.1.11`, pinned tag) behind a public TCP proxy on port 3000, and a private
`valkey` store (`valkey/valkey:9-alpine`) reachable only over Railway's internal network,
with a 500 MB volume at `/data` so site keys and challenge state survive restarts. The
`ADMIN_KEY` dashboard secret is generated automatically by Railway at deploy time — no
secrets are committed to this repo. A healthcheck on `/` catches crash-loops before the
deploy is marked successful.

## Why Deploy

Cap is a proof-of-work CAPTCHA: visitors' browsers solve a short cryptographic puzzle
instead of being profiled by Google. Self-hosting it on Railway keeps every challenge,
token, and verification on infrastructure you control — no third-party JS, no telemetry,
and no per-solve cost. The official Railway template for Cap deploys successfully only
about half the time; this template pins the image tag, wires Valkey with persistence,
generates the admin secret, and verifies the full widget → challenge → verify loop before
publishing, so a one-click deploy just works.

## Common Use Cases

- Protecting login, signup, and contact forms on any stack — the widget is a drop-in web
  component, and `siteverify` is reCAPTCHA-API-compatible, so existing integrations swap
  by changing one URL.
- Privacy-conscious sites (GDPR-heavy, EU-facing) that need to drop reCAPTCHA entirely.
- Self-hosted apps (Git hosting, paste bins, URL shorteners, forums) that want rate-limit
  hardening without external SaaS.
- Agencies running CAPTCHA for many clients: one Cap instance hosts many site keys, each
  with its own secret and difficulty settings from the dashboard.

## Dependencies for

### Deployment Dependencies

None for the app itself — Cap standalone is a single Docker image. The template provisions
its one dependency automatically:

- **Valkey 9** (`valkey/valkey:9-alpine`) — Redis-compatible store for challenges, tokens,
  site keys, and rate-limit counters. Private-network only; `REDIS_URL` is wired to
  `redis://valkey.railway.internal:6379` automatically, with a 500 MB `/data` volume.

Required variables (both auto-generated/auto-wired by the template): `ADMIN_KEY`
(dashboard login — copy it from the `cap` service variables after deploy) and `REDIS_URL`.
Optional tuning: `CORS_ORIGIN`, `ENABLE_ASSETS_SERVER`, `WIDGET_VERSION`, `WASM_VERSION`.
