import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { once } from "node:events";
import { createRoomApi, POLICY } from "./room-api.mjs";
import { createLocalD1 } from "./local-d1.mjs";

const ORIGIN = "https://room-test.invalid";
const AVATAR = { modelId: "SeoulResident_M01", bodyProfile: "standard", swimwear: false };
const BUILD = "test-build-20261025";

function fixture(t) {
  const DB = createLocalD1();
  t.after(() => DB.close());
  let clock = 100000;
  const api = createRoomApi({ now: () => clock });
  return {
    DB, api,
    advance(ms = POLICY.intervalMs) { clock += ms; },
    now() { return clock; },
    async call(path, { user = "owner", method = "POST", data = {}, sessionToken, origin = ORIGIN, headers = {} } = {}) {
      const requestHeaders = { "content-type": "application/json", ...headers };
      if (user) requestHeaders["oai-authenticated-user-id"] = user;
      if (origin !== null) requestHeaders.origin = origin;
      if (sessionToken) requestHeaders.authorization = `Bearer ${sessionToken}`;
      const response = await api(new Request(ORIGIN + path, {
        method, headers: requestHeaders, ...(method !== "GET" ? { body: JSON.stringify(data) } : {}),
      }), { DB });
      return { response, status: response?.status, body: response ? await response.json() : null };
    },
    async create(options = {}) {
      return this.call("/api/multiplayer/rooms", { data: { buildId: BUILD, avatar: AVATAR, position: [10, 1, 20], yaw: 0 }, ...options });
    },
    async join(room, user = "guest", extra = {}) {
      return this.call(`/api/multiplayer/rooms/${room.room.id}/join`, {
        user, data: { invite: room.invite, buildId: BUILD, avatar: AVATAR }, ...extra,
      });
    },
    path(room, player, action) { return `/api/multiplayer/rooms/${room.room.id}/players/${player.selfId}/${action}`; },
  };
}

test("two signed-in players join the same actual SQL room and observe accepted movement", async t => {
  const f = fixture(t);
  const created = await f.create();
  assert.equal(created.status, 201);
  const room = created.body;
  const guest = await f.join(room);
  assert.equal(guest.status, 201);
  assert.equal(guest.body.players.length, 2);
  assert.deepEqual(guest.body.players.find(p => p.id === guest.body.selfId).position, [10, 1, 20]);
  f.advance();
  const moved = await f.call(f.path(room, guest.body, "sync"), {
    user: "guest", sessionToken: guest.body.sessionToken,
    data: { sequence: 1, position: [12, 1, 20], yaw: 0.5, motion: "walk", avatar: { ...AVATAR, bodyProfile: "athletic" } },
  });
  assert.equal(moved.status, 200);
  const seen = await f.call(f.path(room, room, "snapshot"), { method: "GET", sessionToken: room.sessionToken });
  assert.equal(seen.status, 200);
  const other = seen.body.players.find(p => p.id === guest.body.selfId);
  assert.deepEqual(other.position, [12, 1, 20]);
  assert.equal(other.avatar.bodyProfile, "athletic");
  assert.equal(other.motion, "walk");
  assert.equal(other.sequence, 1);
  assert.equal(seen.response.headers.get("cache-control"), "no-store");
});

test("authentication, room invite, account binding and exact origin all gate access", async t => {
  const f = fixture(t);
  assert.equal((await f.create({ user: null })).status, 401);
  assert.equal((await f.create({ origin: "https://other.invalid" })).status, 403);
  assert.equal((await f.create({ origin: null })).status, 403);
  const room = (await f.create()).body;
  const invalidInvite = await f.join(room, "guest", { data: { invite: "0".repeat(32), buildId: BUILD, avatar: AVATAR } });
  assert.equal(invalidInvite.status, 403);
  f.advance();
  assert.equal((await f.call(f.path(room, room, "snapshot"), { method: "GET" })).status, 401);
  assert.equal((await f.call(f.path(room, room, "snapshot"), { method: "GET", user: "other", sessionToken: room.sessionToken })).status, 401);
  assert.equal((await f.call(f.path(room, room, "snapshot"), { method: "GET", sessionToken: room.sessionToken, origin: "https://other.invalid" })).status, 403);
});

test("build mismatches and unrecognized avatar/state fields cannot enter the room", async t => {
  const f = fixture(t);
  const room = (await f.create()).body;
  assert.equal((await f.join(room, "guest", { data: { invite: room.invite, buildId: "different-build", avatar: AVATAR } })).status, 409);
  assert.equal((await f.join(room, "guest", { data: { invite: room.invite, buildId: BUILD, avatar: { ...AVATAR, modelId: "arbitrary_path" } } })).status, 400);
  f.advance();
  assert.equal((await f.call(f.path(room, room, "sync"), {
    sessionToken: room.sessionToken,
    data: { sequence: 1, position: [10, 1, 20], yaw: 0, motion: "walk", email: "never-store@example.invalid" },
  })).status, 400);
});

test("snapshot and movement share the two-Hz mutation limit; stale/reordered sequences are rejected", async t => {
  const f = fixture(t);
  const room = (await f.create()).body;
  const sync = sequence => f.call(f.path(room, room, "sync"), {
    sessionToken: room.sessionToken, data: { sequence, position: [10, 1, 20], yaw: 0, motion: "idle" },
  });
  const limited = await sync(1);
  assert.equal(limited.status, 429);
  assert.equal(limited.body.retryAfterMs, POLICY.intervalMs);
  f.advance();
  assert.equal((await sync(2)).status, 200);
  assert.equal((await f.call(f.path(room, room, "snapshot"), { method: "GET", sessionToken: room.sessionToken })).status, 429);
  f.advance();
  assert.equal((await sync(1)).status, 409);
});

test("accepted yaw endpoints and adjacent headings survive create/snapshot/sync round trips", async t => {
  for (const heading of [Math.PI, -Math.PI, Math.PI - 1e-7, -Math.PI + 1e-7]) {
    const f = fixture(t);
    const created = await f.create({ data: { buildId: BUILD, avatar: AVATAR, position: [10, 1, 20], yaw: heading } });
    assert.equal(created.status, 201);
    const room = created.body;
    const accepted = room.players.find(player => player.id === room.selfId);
    assert.equal(accepted.yaw, heading);
    assert.ok(Math.abs(accepted.yaw) <= Math.PI);
    f.advance();
    const synced = await f.call(f.path(room, room, "sync"), {
      sessionToken: room.sessionToken,
      data: { sequence: 1, position: accepted.position, yaw: accepted.yaw, motion: "idle" },
    });
    assert.equal(synced.status, 200);
    assert.equal(synced.body.players.find(player => player.id === room.selfId).yaw, heading);
    f.advance();
    const snapshot = await f.call(f.path(room, room, "snapshot"), { method: "GET", sessionToken: room.sessionToken });
    assert.equal(snapshot.status, 200);
    assert.equal(snapshot.body.players.find(player => player.id === room.selfId).yaw, heading);
  }
});

test("atomic admission remains within policy cap when nine guests join concurrently", async t => {
  const f = fixture(t);
  const room = (await f.create()).body;
  const joined = await Promise.all(Array.from({ length: 9 }, (_, n) => f.join(room, `guest-${n}`)));
  assert.equal(joined.filter(x => x.status === 201).length, POLICY.capacity - 1);
  assert.equal(joined.filter(x => x.status === 409).length, 2);
  const count = f.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_players WHERE room_id = ?").get(room.room.id).n;
  assert.equal(count, POLICY.capacity);
});

test("TTL removes silent players and expired room cannot be revived", async t => {
  const f = fixture(t);
  const room = (await f.create()).body;
  const guest = (await f.join(room)).body;
  f.advance(POLICY.presenceTtlMs);
  assert.equal((await f.call(f.path(room, guest, "snapshot"), { user: "guest", method: "GET", sessionToken: guest.sessionToken })).status, 401);
  const fresh = await f.join(room, "fresh");
  assert.equal(fresh.status, 201);
  assert.equal(fresh.body.players.length, 1);
  f.advance(POLICY.roomLifetimeMs);
  assert.equal((await f.join(room, "another")).status, 404);
  // Creation cleans a bounded set of expired rooms and cascades their actors.
  assert.equal((await f.create()).status, 201);
  assert.equal(f.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_players WHERE room_id = ?").get(room.room.id).n, 0);
});

test("rejoin rotates session, prevents duplicate accounts, and observes join cooldown", async t => {
  const f = fixture(t);
  const room = (await f.create()).body;
  const guest1 = (await f.join(room)).body;
  assert.equal((await f.join(room)).status, 429);
  f.advance(POLICY.joinCooldownMs);
  const guest2 = await f.join(room);
  assert.equal(guest2.status, 201);
  assert.equal(guest2.body.players.length, 2);
  assert.notEqual(guest2.body.sessionToken, guest1.sessionToken);
  f.advance();
  assert.equal((await f.call(f.path(room, guest1, "snapshot"), { user: "guest", method: "GET", sessionToken: guest1.sessionToken })).status, 401);
});

test("movement speed, finite coordinates and coarse bounds reject invalid state without advancing sequence", async t => {
  const f = fixture(t);
  const room = (await f.create()).body;
  f.advance();
  const sync = position => f.call(f.path(room, room, "sync"), {
    sessionToken: room.sessionToken, data: { sequence: 1, position, yaw: 0, motion: "run" },
  });
  assert.equal((await sync([100, 1, 20])).status, 422);
  assert.equal((await sync([2000, 1, 20])).status, 422);
  assert.equal((await sync([null, 1, 20])).status, 400);
  assert.equal((await sync([11, 1, 20])).status, 200);
});

test("optimistic SQL update allows only one concurrent state writer per player", async t => {
  const f = fixture(t);
  const room = (await f.create()).body;
  f.advance();
  const results = await Promise.all([1, 2].map(sequence => f.call(f.path(room, room, "sync"), {
    sessionToken: room.sessionToken, data: { sequence, position: [11, 1, 20], yaw: 0, motion: "walk" },
  })));
  assert.equal(results.filter(x => x.status === 200).length, 1);
  assert.equal(results.filter(x => [409, 429].includes(x.status)).length, 1);
});

test("room owner can close, members can leave, and creation has cooldown and an active-room cap", async t => {
  const f = fixture(t);
  const room = (await f.create()).body;
  const guest = (await f.join(room)).body;
  assert.equal((await f.call(`/api/multiplayer/rooms/${room.room.id}/close`, { user: "guest" })).status, 403);
  assert.equal((await f.call(f.path(room, guest, "leave"), { user: "guest", sessionToken: guest.sessionToken })).status, 200);
  assert.equal((await f.create()).status, 429);
  f.advance(POLICY.createCooldownMs);
  assert.equal((await f.create()).status, 201);
  f.advance(POLICY.createCooldownMs);
  const capped = await f.create();
  assert.equal(capped.status, 429);
  assert.equal(capped.body.error, "active_room_limit");
  assert.equal((await f.call(`/api/multiplayer/rooms/${room.room.id}/close`)).status, 200);
  assert.equal(f.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_players WHERE room_id = ?").get(room.room.id).n, 0);
});

test("snapshots contain only pseudonymous public state; credentials are hashed in storage", async t => {
  const f = fixture(t);
  const room = (await f.create({ user: "site-stable-user-id-private" })).body;
  const guest = await f.join(room, "guest-private-id");
  assert.equal(guest.status, 201);
  const snapshotText = JSON.stringify({ room: guest.body.room, players: guest.body.players });
  for (const secret of [room.invite, room.sessionToken, "site-stable-user-id-private", "guest-private-id", "owner_key", "token_hash", "invite_hash", "user_key"]) {
    assert.equal(snapshotText.includes(secret), false);
  }
  const stored = JSON.stringify({
    rooms: f.DB.sqlite.prepare("SELECT * FROM multiplayer_rooms").all(),
    players: f.DB.sqlite.prepare("SELECT * FROM multiplayer_players").all(),
    rates: f.DB.sqlite.prepare("SELECT * FROM multiplayer_rate_limits").all(),
  });
  for (const secret of [room.invite, room.sessionToken, guest.body.sessionToken, "site-stable-user-id-private", "guest-private-id"]) {
    assert.equal(stored.includes(secret), false);
  }
});

test("oversized/malformed bodies, unknown routes and unavailable database fail without leaking internals", async t => {
  const f = fixture(t);
  assert.equal((await f.create({ data: { padding: "x".repeat(2200) } })).status, 413);
  assert.equal((await f.call("/api/multiplayer/not-a-route")).status, 404);
  assert.equal(await f.api(new Request(ORIGIN + "/"), { DB: f.DB }), null);
  const missing = await f.api(new Request(ORIGIN + "/api/multiplayer/rooms", {
    method: "POST", headers: { "oai-authenticated-user-id": "owner", origin: ORIGIN },
  }), {});
  assert.equal(missing.status, 503);
  const broken = await f.api(new Request(ORIGIN + "/api/multiplayer/rooms", {
    method: "POST", headers: { "oai-authenticated-user-id": "owner", origin: ORIGIN, "content-type": "application/json" },
    body: JSON.stringify({ buildId: BUILD, avatar: AVATAR, position: [10, 1, 20], yaw: 0 }),
  }), { DB: { prepare() { throw new Error("secret-database-details"); }, batch() {} } });
  assert.equal(broken.status, 503);
  assert.equal((await broken.text()).includes("secret-database-details"), false);
});

test("loopback HTTP smoke: two separate clients create, join, move and see the same room", async t => {
  const f = fixture(t);
  const server = createServer(async (incoming, outgoing) => {
    // Test-only identity adapter, loopback only; NEVER deploy this adapter.
    const headers = new Headers(incoming.headers);
    const testUser = headers.get("x-local-test-user");
    headers.delete("x-local-test-user");
    if (testUser) headers.set("oai-authenticated-user-id", testUser);
    const chunks = [];
    for await (const chunk of incoming) chunks.push(chunk);
    const request = new Request(`http://127.0.0.1:${server.address().port}${incoming.url}`, {
      method: incoming.method, headers,
      ...(incoming.method !== "GET" ? { body: Buffer.concat(chunks) } : {}),
    });
    const response = await f.api(request, { DB: f.DB });
    outgoing.writeHead(response?.status ?? 404, Object.fromEntries(response?.headers ?? []));
    outgoing.end(response ? await response.text() : "");
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const origin = `http://127.0.0.1:${server.address().port}`;
  async function http(user, path, data, sessionToken) {
    const response = await fetch(origin + path, {
      method: data ? "POST" : "GET",
      headers: { origin, "content-type": "application/json", "x-local-test-user": user, ...(sessionToken ? { authorization: `Bearer ${sessionToken}` } : {}) },
      ...(data ? { body: JSON.stringify(data) } : {}),
    });
    assert.ok(response.ok, `${response.status} ${await response.clone().text()}`);
    return response.json();
  }
  const room = await http("client-one", "/api/multiplayer/rooms", { buildId: BUILD, avatar: AVATAR, position: [10, 1, 20], yaw: 0 });
  const other = await http("client-two", `/api/multiplayer/rooms/${room.room.id}/join`, { invite: room.invite, buildId: BUILD, avatar: AVATAR });
  f.advance();
  await http("client-two", f.path(room, other, "sync"), { sequence: 1, position: [13, 1, 20], yaw: 1, motion: "run" }, other.sessionToken);
  const seen = await http("client-one", f.path(room, room, "snapshot"), null, room.sessionToken);
  assert.equal(seen.players.length, 2);
  assert.deepEqual(seen.players.find(player => player.id === other.selfId).position, [13, 1, 20]);
});
