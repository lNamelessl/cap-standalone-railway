# Cap — Self-Hosted Proof-of-Work CAPTCHA

Deploy [Cap standalone](https://trycap.dev) — the privacy-first, proof-of-work alternative to
reCAPTCHA — in one click. No Google, no tracking, no per-solve cost. Every challenge and
verification runs on your own Railway project.

## What you get

- **Cap server** (`tiago2/cap:3.1.11`, pinned) with its dashboard and site-key management,
  public on a generated Railway domain (port 3000).
- **Valkey 9** store for challenges, tokens, site keys, and rate-limit counters — reachable only
  over Railway's private network, with a persistent `/data` volume so keys survive restarts.
- **Zero configuration**: the dashboard's `ADMIN_KEY` secret is generated automatically per
  deployment, and `REDIS_URL` is wired to Valkey for you. Nothing to type on the deploy form.

## 60-second self-check

1. Open the `cap` service's public domain — the Cap dashboard loads.
2. Copy `ADMIN_KEY` from the `cap` service variables and log in.
3. Create a site key; note the site key (public) and secret key (private).
4. Add the widget to any page (must be a public origin, not localhost):

   ```html
   &lt;script src="https://cdn.jsdelivr.net/npm/cap-widget@latest"&gt;&lt;/script&gt;
   &lt;cap-widget data-cap-api-endpoint="https://YOUR-DOMAIN/YOUR-SITE-KEY/"&gt;&lt;/cap-widget&gt;
   ```

5. Verify a solved token server-side — the endpoint is reCAPTCHA-compatible:

   ```bash
   curl -X POST https://YOUR-DOMAIN/YOUR-SITE-KEY/siteverify \
     -H 'Content-Type: application/json' \
     -d '{"secret": "YOUR-SECRET-KEY", "response": "TOKEN"}'
   # → {"success": true}
   ```

Prefer a scripted check? The [repo](https://github.com/lNamelessl/cap-standalone-railway)
ships `scripts/roundtrip.mjs`, which fetches a challenge, solves the same proof-of-work the
widget solves, redeems it, and verifies it via `siteverify` — a full
challenge → solve → redeem → verify round-trip without a browser.

## Troubleshooting

- **Widget fails on a custom domain** — set `CORS_ORIGIN` on the `cap` service to your site's
  origin(s), comma-separated. The default `*` works for any origin out of the box.
- **Dashboard login rejected** — use the `ADMIN_KEY` service variable, not a site secret key.
  These are different credentials; mixing them up is the most common Cap setup mistake.
- **`siteverify` returns 404** — the site key is part of the path: `/YOUR-SITE-KEY/siteverify`.
- **Why no deploy healthcheck?** Cap's router returns 404 for requests that don't carry one of
  its public hostnames, and Railway's healthcheck probes use the internal hostname — so an HTTP
  healthcheck path reliably marks good deploys as failed. This template omits the healthcheck
  and relies on the `ON_FAILURE` restart policy (10 retries) instead.

---

# Deploy and Host

## About Hosting

Hosting Cap on Railway runs two small containers: the `cap` server (`tiago2/cap:3.1.11`, a
pinned upstream tag) behind a public domain on port 3000, and a private `valkey` store
(`valkey/valkey:9-alpine`) reachable only over Railway's internal network, with a `/data`
volume so site keys and in-flight challenges survive restarts and redeploys. The dashboard
login secret (`ADMIN_KEY`) is generated fresh for every deployment by Railway's secret
generator — no secrets are stored in the template or the repo — and `REDIS_URL` points at
Valkey via a service reference, so the deploy form asks for nothing.

## Why Deploy

Cap is a proof-of-work CAPTCHA: the visitor's browser solves a short cryptographic puzzle
instead of being profiled by an advertising company. Self-hosting on Railway keeps every
challenge, token, and verification on infrastructure you control — no third-party JavaScript,
no telemetry, and no per-solve billing. Cap's own official Railway template fails on roughly
half its deploys; this template pins the image tag, wires persistent storage, generates
secrets automatically, skips the HTTP healthcheck that breaks Cap's host-based router, and was
verified with repeated fresh deploys plus a full widget → challenge → verify round-trip before
publishing. Both services idle in well under 512 MB combined — expect roughly $3–5/month.

## Common Use Cases

- Protecting login, signup, and contact forms on any stack — the widget is a drop-in web
  component, and `siteverify` is reCAPTCHA-API-compatible, so many existing integrations swap
  by changing one URL.
- Privacy-conscious and EU-facing sites that need to drop reCAPTCHA and third-party trackers.
- Self-hosted apps (Git hosting, forums, URL shorteners, paste bins) that want bot protection
  without an external SaaS dependency.
- Running CAPTCHA for many sites from one instance: a single Cap deployment hosts many site
  keys, each with its own secret and difficulty settings managed from the dashboard.

## Dependencies for

### Deployment Dependencies

None to install — Cap standalone ships as a single Docker image, and the template provisions
its only dependency automatically:

- **Valkey 9** (`valkey/valkey:9-alpine`) — Redis-compatible store for challenges, tokens,
  site keys, and rate-limit counters. Private-network only; `REDIS_URL` is wired to
  `redis://valkey private domain:6379` automatically, with a persistent `/data` volume.

Variables, all auto-provisioned (nothing typed at deploy time): `ADMIN_KEY` — randomly
generated 32-char secret, visible in the `cap` service variables after deploy; `REDIS_URL` —
service reference to Valkey. Optional tuning per the [Cap options](https://trycap.dev/guide/standalone/options.html):
`CORS_ORIGIN`, `ENABLE_ASSETS_SERVER`, `WIDGET_VERSION`, `WASM_VERSION`, `REDIS_PREFIX`.
