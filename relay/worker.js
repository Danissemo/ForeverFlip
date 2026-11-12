// ForeverFlip upload relay: lets players share full auction house scans without a GitHub account.
//
// It runs as a Cloudflare Worker (free plan) with one KV namespace bound as UPLOADS and one secret,
// RELAY_KEY. It holds no GitHub credential and decides nothing about a scan: it only takes the file,
// keeps it for at most three days, and hands it to the data repository's workflow, which checks it
// exactly like a scan uploaded through GitHub (format, age, seal, confirmation by another player,
// agreement with the community's price history) before anything is published.
//
//   POST   /upload             a player's scan (gzip body, X-FF-* headers); no sign-in
//   GET    /pending            waiting scans with their details          (Authorization: Bearer RELAY_KEY)
//   GET    /scan/<id>          one waiting scan                           (same)
//   DELETE /scan/<id>          drop a scan the workflow has handled       (same)
//
// A player is known only as "anon-" and 12 hex digits: an HMAC of their IP address with RELAY_KEY.
// The address itself is never stored.

const MAX_BYTES = 25 * 1024 * 1024; // the largest value KV keeps
const KEEP_SECONDS = 3 * 86400; // a scan nobody collected is dropped
const MAX_AGE = 7 * 86400; // the data repository refuses older scans anyway
const PER_PLAYER = 4; // scans of one player waiting at a time (the workflow runs every 30 minutes)
const WAITING_LIMIT = 300; // scans waiting in all; beyond, uploads are refused until collected

const SCOPE = /^[^|\n\r]{1,80}-(Alliance|Horde|Neutral)$/;
const DIGITS = /^[0-9]{1,12}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const VERSION = /^[0-9A-Za-z.\-]{1,20}$/;
const ID = /^anon-[0-9a-f]{12}\/[0-9a-f]{64}$/;

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function refuse(reason, status = 400) {
  return json({ ok: false, reason }, status);
}

async function hmacHex(key, text) {
  const enc = new TextEncoder();
  const k = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(text)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
}

// Compares the bearer token without leaking how much of it matched.
async function authorized(request, env) {
  const given = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!env.RELAY_KEY || !given) return false;
  const [a, b] = await Promise.all([hmacHex(env.RELAY_KEY, given), hmacHex(env.RELAY_KEY, env.RELAY_KEY)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function count(env, prefix, stopAt) {
  let n = 0;
  let cursor;
  do {
    const page = await env.UPLOADS.list({ prefix, cursor, limit: 1000 });
    n += page.keys.length;
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor && n < stopAt);
  return n;
}

async function upload(request, env) {
  const h = (name) => (request.headers.get(name) || "").trim();
  const scope = h("x-ff-scope");
  const at = h("x-ff-time");
  const seal = h("x-ff-seal");
  const auctions = h("x-ff-auctions");
  const sha256 = h("x-ff-sha256").toLowerCase();
  const helper = h("x-ff-helper");
  if (!SCOPE.test(scope) || !DIGITS.test(at) || !DIGITS.test(seal) || !DIGITS.test(auctions) || !SHA256.test(sha256)
      || !VERSION.test(helper)) {
    return refuse("missing or malformed scan details");
  }
  const now = Math.floor(Date.now() / 1000);
  if (Number(at) > now + 600 || now - Number(at) > MAX_AGE) return refuse("the scan is too old or from the future");
  const length = Number(request.headers.get("content-length") || "0");
  if (!length || length > MAX_BYTES) return refuse("the file is empty or larger than 25 MB", 413);
  if ((request.headers.get("content-type") || "") !== "application/gzip") return refuse("expected a gzip file");

  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  const player = "anon-" + (await hmacHex(env.RELAY_KEY, "player:" + ip)).slice(0, 12);
  const id = `${player}/${sha256}`;
  if ((await env.UPLOADS.list({ prefix: id, limit: 1 })).keys.length) {
    return json({ ok: true, id, uploader: player, already: true });
  }
  if (await count(env, player + "/", PER_PLAYER) >= PER_PLAYER) {
    return refuse("too many of your scans are waiting to be checked; try again in an hour", 429);
  }
  if (await count(env, "", WAITING_LIMIT) >= WAITING_LIMIT) {
    return refuse("the relay is full; try again later", 503);
  }
  const metadata = { scope, at: Number(at), seal: Number(seal), auctions: Number(auctions), sha256, helper,
    uploader: player, received: now, bytes: length };
  // The body streams straight into storage: the relay never parses it.
  await env.UPLOADS.put(id, request.body, { expirationTtl: KEEP_SECONDS, metadata });
  return json({ ok: true, id, uploader: player });
}

async function pending(env, url) {
  const page = await env.UPLOADS.list({ cursor: url.searchParams.get("cursor") || undefined, limit: 100 });
  return json({
    scans: page.keys.map((k) => ({ id: k.name, ...(k.metadata || {}) })),
    cursor: page.list_complete ? null : page.cursor,
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    try {
      if (request.method === "POST" && path === "/upload") return await upload(request, env);
      if (request.method === "GET" && path === "/") {
        return json({ ok: true, service: "ForeverFlip upload relay" });
      }
      if (!(await authorized(request, env))) return refuse("not allowed", 401);
      if (request.method === "GET" && path === "/pending") return await pending(env, url);
      const m = path.match(/^\/scan\/(.+)$/);
      if (m && ID.test(m[1])) {
        if (request.method === "GET") {
          const value = await env.UPLOADS.get(m[1], { type: "stream" });
          return value ? new Response(value, { headers: { "content-type": "application/gzip" } }) : refuse("gone", 404);
        }
        if (request.method === "DELETE") {
          await env.UPLOADS.delete(m[1]);
          return json({ ok: true });
        }
      }
      return refuse("unknown request", 404);
    } catch (error) {
      return refuse("relay error: " + (error && error.message ? error.message : String(error)), 500);
    }
  },
};
