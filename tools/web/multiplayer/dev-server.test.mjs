import test from "node:test";
import assert from "node:assert/strict";
import { request as httpRequest } from "node:http";
import { mkdtemp, mkdir, writeFile, symlink, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gzipSync } from "node:zlib";
import { startDevServer, DEV_SESSION } from "./dev-server.mjs";
import { POLICY } from "./room-api.mjs";

const AVATAR = { modelId: "SeoulResident_M01", bodyProfile: "standard", swimwear: false };
const BUILD = "local-feature-20261026";
async function fixture(t, options = {}) {
  let clock = 100_000;
  const host = await startDevServer({ apiOnly: true, port: 0, now: () => clock, ...options });
  t.after(() => host.close());
  assert.equal(host.server.address().address, "127.0.0.1");
  return { ...host, advance(ms = POLICY.intervalMs) { clock += ms; } };
}
function client(host) {
  return {
    cookie: "",
    async call(path, { method = "POST", data = {}, token, origin = host.origin, headers = {} } = {}) {
      const sent = { ...(method === "POST" ? { "content-type": "application/json" } : {}), ...headers };
      if (origin !== null) sent.origin = origin;
      if (this.cookie) sent.cookie = this.cookie;
      if (token) sent.authorization = `Bearer ${token}`;
      const response = await fetch(host.origin + path, { method, headers: sent, ...(method === "POST" ? { body: JSON.stringify(data) } : {}) });
      return { response, status: response.status, body: await response.json() };
    },
    async bootstrap(options = {}) {
      const result = await this.call("/api/multiplayer/dev-session", options);
      if (result.response.headers.get("set-cookie")) this.cookie = result.response.headers.get("set-cookie").split(";", 1)[0];
      return result;
    },
    create(headers = {}) { return this.call("/api/multiplayer/rooms", { data: { buildId: BUILD, avatar: AVATAR, position: [10, 1, 20], yaw: 0 }, headers }); },
    path(room, player, action) { return `/api/multiplayer/rooms/${room.room.id}/players/${player.selfId}/${action}`; },
  };
}
function raw(host, path, { method = "GET", headers = {}, chunks = [] } = {}) {
  return new Promise((accept, reject) => {
    const request = httpRequest(host.origin, { path, method, headers }, response => {
      const parts = [];
      response.on("data", part => parts.push(part));
      response.on("end", () => accept({ status: response.statusCode, headers: response.headers, bytes: Buffer.concat(parts) }));
    });
    request.on("error", reject);
    for (const chunk of chunks) request.write(chunk);
    request.end();
  });
}

test("two real HTTP cookie clients create, join, sync, observe and leave one SQLite room", async t => {
  const host = await fixture(t); const owner = client(host); const guest = client(host);
  const ownerBootstrap = await owner.bootstrap(); const guestBootstrap = await guest.bootstrap();
  assert.equal(ownerBootstrap.status, 200); assert.equal(guestBootstrap.status, 200);
  assert.notEqual(owner.cookie, guest.cookie);
  const setCookie = ownerBootstrap.response.headers.get("set-cookie");
  assert.match(setCookie, /^sim2seoul_dev_\d+=[a-f0-9]{64}; HttpOnly; SameSite=Strict; Path=\/api\/multiplayer\//);
  assert.equal(setCookie.includes("Secure"), false);
  assert.deepEqual(Object.keys(ownerBootstrap.body).sort(), ["developmentOnly", "expiresAtMs"]);
  assert.equal(ownerBootstrap.body.developmentOnly, true);
  const room = (await owner.create({ "oai-authenticated-user-id": "forged-same-user" })).body;
  const entered = await guest.call(`/api/multiplayer/rooms/${room.room.id}/join`, { data: { invite: room.invite, buildId: BUILD, avatar: AVATAR }, headers: { "oai-authenticated-user-id": "forged-same-user" } });
  assert.equal(entered.status, 201); assert.equal(entered.body.players.length, 2);
  host.advance();
  const moved = await guest.call(guest.path(room, entered.body, "sync"), { token: entered.body.sessionToken, data: { sequence: 1, position: [12, 1, 20], yaw: Math.PI, motion: "walk", avatar: { ...AVATAR, bodyProfile: "athletic" } } });
  assert.equal(moved.status, 200);
  const snapshot = await owner.call(owner.path(room, room, "snapshot"), { method: "GET", origin: null, token: room.sessionToken });
  assert.equal(snapshot.status, 200);
  const other = snapshot.body.players.find(player => player.id === entered.body.selfId);
  assert.deepEqual(other.position, [12, 1, 20]); assert.equal(other.yaw, Math.PI); assert.equal(other.avatar.bodyProfile, "athletic");
  assert.equal((await guest.call(guest.path(room, entered.body, "leave"), { token: entered.body.sessionToken })).body.left, true);
  host.advance();
  const after = await owner.call(owner.path(room, room, "snapshot"), { method: "GET", token: room.sessionToken });
  assert.equal(after.body.players.length, 1);
});

test("public local status, idempotent bootstrap and valid-cookie identity binding", async t => {
  const host = await fixture(t); const owner = client(host); const guest = client(host);
  const status = await owner.call("/api/multiplayer/status", { method: "GET", origin: null });
  assert.deepEqual(status.body, { available: true, apiVersion: 1, mode: "local_development" });
  assert.equal(status.response.headers.get("access-control-allow-origin"), null);
  await owner.bootstrap(); await guest.bootstrap(); const cookie = owner.cookie;
  const room = (await owner.create()).body;
  await owner.bootstrap(); assert.equal(owner.cookie, cookie);
  host.advance();
  assert.equal((await owner.call(owner.path(room, room, "snapshot"), { method: "GET", token: room.sessionToken })).status, 200);
  assert.equal((await guest.call(owner.path(room, room, "snapshot"), { method: "GET", token: room.sessionToken, headers: { "OAI-Authenticated-User-ID": "anything" } })).status, 401);
});

test("unissued cookies, untrusted identity headers and bootstrap account fields cannot authenticate", async t => {
  const host = await fixture(t); const outsider = client(host);
  assert.equal((await outsider.create({ "oai-authenticated-user-id": "owner", "x-local-test-user": "owner" })).status, 401);
  outsider.cookie = `${host.cookieName}=${"a".repeat(64)}`;
  assert.equal((await outsider.create({ "oai-authenticated-user-id": "owner" })).status, 401);
  assert.equal((await outsider.bootstrap({ data: { accountId: "owner" } })).status, 400);
  assert.equal((await outsider.bootstrap()).status, 200);
  assert.notEqual(outsider.cookie, `${host.cookieName}=${"a".repeat(64)}`);
  assert.equal((await outsider.create()).status, 201);
});

test("exact Origin, Host, request target and cookie ambiguity gates are enforced without CORS", async t => {
  const host = await fixture(t); const user = client(host);
  for (const origin of [null, "https://other.invalid", host.origin.replace("127.0.0.1", "localhost")]) {
    const result = await user.bootstrap({ origin }); assert.equal(result.status, 403);
    assert.equal(result.response.headers.get("access-control-allow-origin"), null);
  }
  assert.equal((await raw(host, "/api/multiplayer/status", { headers: { host: "other.invalid" } })).status, 403);
  assert.equal((await raw(host, host.origin + "/api/multiplayer/status")).status, 400);
  assert.equal((await raw(host, "//other.invalid/api/multiplayer/status")).status, 400);
  assert.equal((await user.call("/api/multiplayer/status", { method: "GET", origin: "https://other.invalid" })).status, 403);
  await user.bootstrap(); user.cookie += "; " + user.cookie;
  assert.equal((await user.create()).status, 400);
});

test("session expiry and bounded bootstrap capacity retain server-issued session semantics", async t => {
  const host = await fixture(t); const user = client(host);
  await user.bootstrap(); const first = user.cookie;
  host.advance(DEV_SESSION.lifetimeMs + 1);
  assert.equal((await user.create()).status, 401);
  await user.bootstrap(); assert.notEqual(user.cookie, first);
  for (let index = 1; index < DEV_SESSION.capacity; index++) assert.equal((await client(host).bootstrap()).status, 200);
  assert.equal((await client(host).bootstrap()).status, 429);
  assert.equal((await user.bootstrap()).status, 200);
});

test("bootstrap and room body limits apply to declared and chunked HTTP bodies", async t => {
  const host = await fixture(t); const user = client(host);
  const oversized = JSON.stringify({ padding: "x".repeat(POLICY.maximumBodyBytes) });
  const headers = { origin: host.origin, "content-type": "application/json" };
  assert.equal((await raw(host, "/api/multiplayer/dev-session", { method: "POST", headers: { ...headers, "content-length": Buffer.byteLength(oversized) }, chunks: [oversized] })).status, 413);
  assert.equal((await raw(host, "/api/multiplayer/dev-session", { method: "POST", headers: { ...headers, "transfer-encoding": "chunked" }, chunks: [oversized.slice(0, 1000), oversized.slice(1000)] })).status, 413);
  assert.equal((await raw(host, "/api/multiplayer/dev-session", { method: "POST", headers, chunks: ["{"] })).status, 400);
  await user.bootstrap();
  assert.equal((await user.call("/api/multiplayer/rooms", { data: { padding: "x".repeat(2200) } })).status, 413);
  const valid = JSON.stringify({ buildId: BUILD, avatar: AVATAR, position: [10, 1, 20], yaw: 0 });
  const forwarded = await raw(host, "/api/multiplayer/rooms", { method: "POST", headers: { ...headers, cookie: user.cookie, "transfer-encoding": "chunked" }, chunks: [valid.slice(0, 9), valid.slice(9)] });
  assert.equal(forwarded.status, 201); assert.ok(JSON.parse(forwarded.bytes).room.id);
});

test("static whitelist serves exact gzip bytes and HEAD while rejecting traversal, sources and symlink escapes", async t => {
  const directory = await mkdtemp(join(tmpdir(), "sim2seoul-dev-host-")); t.after(() => rm(directory, { recursive: true, force: true }));
  const dist = join(directory, "dist"); await mkdir(join(dist, "game"), { recursive: true }); await mkdir(join(dist, "chunks"));
  await writeFile(join(dist, "index.html"), "<title>fixture</title>"); await writeFile(join(dist, "play.html"), "fixture game"); await writeFile(join(dist, "game", "manifest.json"), "{}");
  await writeFile(join(dist, "game", "index.audio.worklet.js"), "// fixture worklet");
  const packed = gzipSync(Buffer.from("exact compressed fixture bytes")); await writeFile(join(dist, "chunks", "fixture.gz"), packed);
  await writeFile(join(directory, "private.txt"), "private outside export"); await writeFile(join(dist, "private.txt"), "unlisted inside export");
  await symlink(join(directory, "private.txt"), join(dist, "chunks", "escape.gz"));
  const host = await fixture(t, { dist, apiOnly: false });
  const served = await raw(host, "/chunks/fixture.gz?release=test");
  assert.equal(served.status, 200); assert.deepEqual(served.bytes, packed); assert.equal(served.headers["content-type"], "application/gzip");
  assert.equal(served.headers["content-encoding"], undefined); assert.equal(served.headers.location, undefined);
  const head = await raw(host, "/chunks/fixture.gz", { method: "HEAD" });
  assert.equal(head.status, 200); assert.equal(head.bytes.length, 0); assert.equal(Number(head.headers["content-length"]), packed.length);
  assert.equal((await raw(host, "/")).status, 200); assert.equal((await raw(host, "/game/index.audio.worklet.js")).status, 200);
  for (const path of ["/private.txt", "/.git/config", "/game/scripts/private.gd", "/data/cache/private.json", "/chunks/escape.gz", "/chunks/", "/chunks/missing.gz"]) assert.equal((await raw(host, path)).status, 404, path);
  for (const path of ["/../private.txt", "/%2e%2e/private.txt", "/chunks/%2e%2e/private.txt", "/chunks%2ffixture.gz", "/chunks/%5cprivate.gz", "/chunks/%00.gz"]) assert.equal((await raw(host, path)).status, 400, path);
  assert.equal((await raw(host, "/chunks/fixture.gz", { method: "POST" })).status, 405);
});

test("API-only host exposes no static files and startup rejects an invalid export or port", async t => {
  const host = await fixture(t);
  assert.equal((await raw(host, "/")).status, 404);
  assert.equal((await raw(host, "/game/manifest.json")).status, 404);
  await assert.rejects(startDevServer({ apiOnly: true, port: -1 }), /Invalid local port/);
  await assert.rejects(startDevServer({ port: 0 }), /--dist is required/);
  await assert.rejects(startDevServer({ port: 0, dist: new URL(".", import.meta.url).pathname }));
});
