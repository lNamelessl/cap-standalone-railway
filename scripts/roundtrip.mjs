#!/usr/bin/env node
// Prove a Cap standalone deployment end to end:
// challenge -> solve (sha256 PoW, same algorithm as @cap.js widget) -> redeem -> siteverify.
// Usage: node scripts/roundtrip.mjs https://<your-domain> <site_key> <secret_key>
// Mirrors capjs-core (validateChallenge): salts/targets derived from the challenge token
// via FNV-1a + xorshift PRNG; solution = integer n such that sha256(salt + n) starts with target.
import crypto from "crypto";

const [base, siteKey, secret] = process.argv.slice(2);
if (!base || !siteKey || !secret) {
  console.error("usage: node scripts/roundtrip.mjs https://<domain> <site_key> <secret_key>");
  process.exit(2);
}
const api = base.replace(/\/$/, "") + "/" + siteKey;

function fnv1aResume(h, str) {
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h += (h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24);
  }
  return h >>> 0;
}
function fnv1a(str) { return fnv1aResume(2166136261, str); }
function prngFromHash(seed, len) {
  let s = seed >>> 0, out = "";
  while (out.length < len) {
    s ^= s << 13; s ^= s >>> 17; s ^= s << 5; s >>>= 0;
    out += s.toString(16).padStart(8, "0");
  }
  return out.slice(0, len);
}
function solve({ token, c, s, d }) {
  const tf = fnv1a(token), solutions = [];
  for (let i = 0; i < c; i++) {
    const saltSeed = fnv1aResume(tf, String(i + 1));
    const target = prngFromHash(fnv1aResume(saltSeed, "d"), d);
    const salt = prngFromHash(saltSeed, s);
    for (let n = 0; ; n++) {
      if (crypto.createHash("sha256").update(salt + n).digest("hex").startsWith(target)) {
        solutions.push(n); break;
      }
    }
  }
  return solutions;
}

const post = (url, body) => fetch(url, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
}).then(async r => ({ status: r.status, body: await r.json() }));

const t0 = Date.now();
const ch = await post(api + "/challenge", {});
if (!ch.body.token) { console.error("challenge failed:", ch); process.exit(1); }
console.log(`challenge: c=${ch.body.challenge.c} d=${ch.body.challenge.d} (HTTP ${ch.status})`);

const solutions = solve({ token: ch.body.token, ...ch.body.challenge });
console.log(`solved ${solutions.length} puzzles in ${Date.now() - t0}ms`);

const redeem = await post(api + "/redeem", { token: ch.body.token, solutions });
if (!redeem.body.token) { console.error("redeem failed:", redeem); process.exit(1); }
console.log(`redeem: OK (HTTP ${redeem.status}, token expires ${new Date(redeem.body.expires).toISOString()})`);

const verify = await post(api + "/siteverify", { secret, response: redeem.body.token });
console.log(`siteverify: HTTP ${verify.status} -> ${JSON.stringify(verify.body)}`);
const reuse = await post(api + "/siteverify", { secret, response: redeem.body.token });
console.log(`reuse of same token (must fail, single-use): HTTP ${reuse.status} -> ${JSON.stringify(reuse.body)}`);
process.exit(verify.body.success === true && reuse.body.success !== true ? 0 : 1);
