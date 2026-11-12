// Runs the upload relay (relay/worker.js) against an in-memory KV; tests/test_relay.py starts it.
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import path from "node:path";

const worker = (await import(pathToFileURL(path.resolve("relay/worker.js")).href)).default;

class FakeKV {
  constructor() { this.data = new Map(); }
  async put(key, value, options = {}) {
    const bytes = new Uint8Array(await new Response(value).arrayBuffer());
    this.data.set(key, { bytes, metadata: options.metadata, ttl: options.expirationTtl });
  }
  async get(key, options = {}) {
    const v = this.data.get(key);
    if (!v) return null;
    return options.type === "stream" ? new Response(v.bytes).body : v.bytes;
  }
  async list({ prefix = "", limit = 1000 } = {}) {
    const keys = [...this.data.keys()].filter((k) => k.startsWith(prefix)).sort().slice(0, limit)
      .map((name) => ({ name, metadata: this.data.get(name).metadata }));
    return { keys, list_complete: true };
  }
  async delete(key) { this.data.delete(key); }
}

const env = { UPLOADS: new FakeKV(), RELAY_KEY: "test-relay-key" };
const now = Math.floor(Date.now() / 1000);
const body = new Uint8Array([0x1f, 0x8b, 8, 0, 1, 2, 3, 4]);
const sha = (n) => n.toString(16).padStart(64, "0");

function send(headers = {}, ip = "198.51.100.7", payload = body) {
  return worker.fetch(new Request("https://relay.example/upload", {
    method: "POST",
    body: payload,
    headers: {
      "content-type": "application/gzip", "content-length": String(payload.length), "cf-connecting-ip": ip,
      "x-ff-scope": "Realm 3 PvE-Alliance", "x-ff-time": String(now - 60), "x-ff-seal": "123456",
      "x-ff-auctions": "1000", "x-ff-sha256": sha(1), "x-ff-helper": "1.2.0", ...headers,
    },
  }), env);
}
const authed = (method, p) => worker.fetch(new Request("https://relay.example" + p,
  { method, headers: { authorization: "Bearer test-relay-key" } }), env);

// An upload is kept with its details and an anonymous player id, never the address.
let r = await send();
assert.equal(r.status, 200);
let answer = await r.json();
assert.match(answer.uploader, /^anon-[0-9a-f]{12}$/);
const stored = env.UPLOADS.data.get(answer.id);
assert.equal(stored.metadata.scope, "Realm 3 PvE-Alliance");
assert.equal(stored.ttl, 3 * 86400);
assert.ok(!JSON.stringify(stored.metadata).includes("198.51.100.7"));
assert.deepEqual([...stored.bytes], [...body]);

// The same scan again is not stored twice.
r = await send();
assert.equal((await r.json()).already, true);
assert.equal(env.UPLOADS.data.size, 1);

// Malformed details, old scans, other files and oversized files are refused.
assert.equal((await send({ "x-ff-scope": "Realm-Pirates", "x-ff-sha256": sha(2) })).status, 400);
assert.equal((await send({ "x-ff-time": String(now - 8 * 86400), "x-ff-sha256": sha(3) })).status, 400);
assert.equal((await send({ "content-type": "text/plain", "x-ff-sha256": sha(4) })).status, 400);
assert.equal((await send({ "content-length": String(26 * 1024 * 1024), "x-ff-sha256": sha(5) })).status, 413);

// One player may have four scans waiting; another player is not affected.
for (let n = 10; n < 13; n++) assert.equal((await send({ "x-ff-sha256": sha(n) })).status, 200);
assert.equal((await send({ "x-ff-sha256": sha(20) })).status, 429);
assert.equal((await send({ "x-ff-sha256": sha(21) }, "203.0.113.9")).status, 200);

// Reading and deleting need the key.
assert.equal((await worker.fetch(new Request("https://relay.example/pending"), env)).status, 401);
assert.equal((await worker.fetch(new Request("https://relay.example/pending",
  { headers: { authorization: "Bearer wrong" } }), env)).status, 401);
const list = await (await authed("GET", "/pending")).json();
assert.equal(list.scans.length, 5);
assert.ok(list.scans.every((s) => s.uploader && s.sha256 && s.scope));
const one = await authed("GET", "/scan/" + answer.id);
assert.deepEqual([...new Uint8Array(await one.arrayBuffer())], [...body]);
assert.equal((await authed("DELETE", "/scan/" + answer.id)).status, 200);
assert.equal((await authed("GET", "/scan/" + answer.id)).status, 404);
assert.equal((await authed("GET", "/scan/../../etc")).status, 404);

console.log("relay ok");
