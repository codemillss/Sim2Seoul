import test from "node:test";
import assert from "node:assert/strict";
import { createRoomApi, POLICY } from "./room-api.mjs";
import { createLocalD1 } from "./local-d1.mjs";

const ORIGIN = "https://cleanup-fixture.invalid";
const AVATAR = { modelId: "SeoulResident_M01", bodyProfile: "standard", swimwear: false };
const WORLD = { entities: [{ id: "npc:0", kind: "npc", position: [0, 0, 0], rotation: [0, 0, 0], velocity: [0, 0, 0], motion: "idle" }] };
function fixture(t) {
  const DB = createLocalD1(); t.after(() => DB.close()); let time = 100_000;
  const api = createRoomApi({ now: () => time });
  return { DB, advance(ms) { time += ms; }, now: () => time,
    async create(user = "owner", world = true) {
      const response = await api(new Request(ORIGIN + "/api/multiplayer/rooms", {
        method: "POST", headers: { origin: ORIGIN, "content-type": "application/json", "oai-authenticated-user-id": user },
        body: JSON.stringify({ buildId: "cleanup-fixture-v2", avatar: AVATAR, position: [0, 0, 0], yaw: 0, ...(world ? { world: WORLD } : {}) }),
      }), { DB });
      return { status: response.status, body: await response.json() };
    },
    count(table, roomId) { return DB.sqlite.prepare(`SELECT COUNT(*) AS n FROM ${table}` + (roomId ? " WHERE " + (table === "multiplayer_rooms" ? "id" : "room_id") + " = ?" : "")).get(...(roomId ? [roomId] : [])).n; },
  };
}
async function twoRooms(f, user = "owner", world = true) {
  const first = await f.create(user, world); assert.equal(first.status, 201);
  f.advance(POLICY.createCooldownMs); const second = await f.create(user, world); assert.equal(second.status, 201);
  return [first.body, second.body];
}

test("expired own world hosts free replacement capacity without a snapshot read", async t => {
  const f = fixture(t), old = await twoRooms(f); f.advance(POLICY.presenceTtlMs);
  const replacement = await f.create(); assert.equal(replacement.status, 201); assert.equal(f.count("multiplayer_rooms"), 1);
  for (const room of old) for (const table of ["multiplayer_rooms", "multiplayer_players", "multiplayer_worlds"]) assert.equal(f.count(table, room.room.id), 0);
});
test("missing own host releases its world and cascades members and receipts", async t => {
  const f = fixture(t), old = await twoRooms(f); const room = old[0];
  f.DB.sqlite.prepare("INSERT INTO multiplayer_world_actions VALUES (?, ?, ?, ?, ?, ?)").run(room.room.id, room.selfId, crypto.randomUUID(), "hash", "{}", f.now());
  f.DB.sqlite.prepare("DELETE FROM multiplayer_players WHERE id = ?").run(room.selfId);
  f.advance(POLICY.createCooldownMs); assert.equal((await f.create()).status, 201);
  assert.equal(f.count("multiplayer_world_actions", room.room.id), 0); assert.equal(f.count("multiplayer_rooms", old[1].room.id), 1);
});
test("live guest does not retain a world whose host expired", async t => {
  const f = fixture(t), old = await twoRooms(f); f.advance(POLICY.presenceTtlMs);
  const host = f.DB.sqlite.prepare("SELECT * FROM multiplayer_players WHERE id = ?").get(old[0].selfId);
  f.DB.sqlite.prepare(`INSERT INTO multiplayer_players (id,room_id,user_key,token_hash,avatar_json,x,y,z,last_action_ms,last_position_ms,last_seen_ms) VALUES (?,?,?,?,?,?,?,?,?,?,?)`)
    .run(crypto.randomUUID(), old[0].room.id, "fixture-guest", "fixture-hash", host.avatar_json, 0, 0, 0, f.now(), f.now(), f.now());
  assert.equal((await f.create()).status, 201); assert.equal(f.count("multiplayer_players", old[0].room.id), 0);
});
test("live own host at cutoff plus one millisecond survives; cutoff equality expires", async t => {
  const f = fixture(t), old = await twoRooms(f); f.advance(POLICY.presenceTtlMs);
  f.DB.sqlite.prepare("UPDATE multiplayer_players SET last_seen_ms = ? WHERE id = ?").run(f.now() - POLICY.presenceTtlMs + 1, old[0].selfId);
  assert.equal((await f.create()).status, 201);
  assert.equal(f.count("multiplayer_rooms", old[0].room.id), 1); assert.equal(f.count("multiplayer_rooms", old[1].room.id), 0);
});
test("live own worlds remain capped and create cooldown still runs before cleanup", async t => {
  const f = fixture(t), old = await twoRooms(f); f.advance(POLICY.createCooldownMs);
  const capped = await f.create(); assert.equal(capped.status, 429); assert.equal(capped.body.error, "active_room_limit");
  f.DB.sqlite.prepare("DELETE FROM multiplayer_players WHERE id = ?").run(old[0].selfId);
  f.advance(1); const fast = await f.create(); assert.equal(fast.status, 429); assert.equal(fast.body.error, "account_action_rate_limited");
  assert.equal(f.count("multiplayer_rooms", old[0].room.id), 1);
  f.advance(POLICY.createCooldownMs); assert.equal((await f.create()).status, 201);
});
test("another owner's stale world is preserved by same-owner cleanup", async t => {
  const f = fixture(t), other = await twoRooms(f, "other"), own = await twoRooms(f, "owner");
  f.advance(POLICY.presenceTtlMs); assert.equal((await f.create("owner")).status, 201);
  for (const room of other) assert.equal(f.count("multiplayer_rooms", room.room.id), 1);
  for (const room of own) assert.equal(f.count("multiplayer_rooms", room.room.id), 0);
});
test("legacy rooms are preserved and still consume owner capacity after host TTL", async t => {
  const f = fixture(t), old = await twoRooms(f, "owner", false); f.advance(POLICY.presenceTtlMs + 1);
  const response = await f.create(); assert.equal(response.status, 429); assert.equal(response.body.error, "active_room_limit");
  for (const room of old) assert.equal(f.count("multiplayer_rooms", room.room.id), 1);
});
test("a stale shared world is removed without deleting the same owner's legacy room", async t => {
  const f = fixture(t), legacy = await f.create("owner", false); f.advance(POLICY.createCooldownMs);
  const world = await f.create(); f.advance(POLICY.presenceTtlMs);
  assert.equal((await f.create()).status, 201);
  assert.equal(f.count("multiplayer_rooms", legacy.body.room.id), 1); assert.equal(f.count("multiplayer_rooms", world.body.room.id), 0);
});
test("concurrent replacement creates still admit one same-owner request and preserve the cap", async t => {
  const f = fixture(t); await twoRooms(f); f.advance(POLICY.presenceTtlMs);
  const results = await Promise.all([f.create(), f.create()]);
  assert.equal(results.filter(row => row.status === 201).length, 1); assert.equal(results.filter(row => row.status === 429).length, 1);
  assert.equal(f.count("multiplayer_rooms"), 1);
});
test("a host heartbeat committed immediately before the create batch is respected", async t => {
  const f = fixture(t), old = await twoRooms(f); f.advance(POLICY.presenceTtlMs);
  const original = f.DB.batch.bind(f.DB); let armed = true;
  f.DB.batch = async statements => {
    if (armed) { armed = false; f.DB.sqlite.prepare("UPDATE multiplayer_players SET last_seen_ms = ? WHERE id = ?").run(f.now(), old[0].selfId); }
    return original(statements);
  };
  assert.equal((await f.create()).status, 201); assert.equal(f.count("multiplayer_rooms", old[0].room.id), 1); assert.equal(f.count("multiplayer_rooms", old[1].room.id), 0);
});
test("failure later in the create transaction rolls cleanup back", async t => {
  const f = fixture(t), old = await twoRooms(f); f.advance(POLICY.presenceTtlMs);
  const original = f.DB.batch.bind(f.DB);
  f.DB.batch = statements => original([...statements, f.DB.prepare("INSERT INTO deliberately_missing_fixture_table VALUES (1)")]);
  assert.equal((await f.create()).status, 503);
  for (const room of old) assert.equal(f.count("multiplayer_rooms", room.room.id), 1);
  assert.equal(f.count("multiplayer_rooms"), 2);
});
test("cleanup is bounded even for an over-cap fixture database", async t => {
  const f = fixture(t), original = await f.create(); assert.equal(original.status, 201);
  const row = f.DB.sqlite.prepare("SELECT * FROM multiplayer_rooms").get(); f.DB.sqlite.prepare("DELETE FROM multiplayer_players").run();
  for (let i = 0; i < 39; i += 1) {
    const id = crypto.randomUUID();
    f.DB.sqlite.prepare("INSERT INTO multiplayer_rooms VALUES (?,?,?,?,?,?,?,?,?)").run(id, row.owner_key, row.invite_hash, row.build_id, 0, 0, 0, f.now(), row.expires_ms);
    f.DB.sqlite.prepare("INSERT INTO multiplayer_worlds VALUES (?,?,?,?,?)").run(id, crypto.randomUUID(), 0, "{}", f.now());
  }
  f.advance(POLICY.createCooldownMs); const first = await f.create(); assert.equal(first.status, 429); assert.equal(first.body.error, "active_room_limit");
  assert.equal(f.count("multiplayer_rooms"), 8);
  f.advance(POLICY.createCooldownMs); assert.equal((await f.create()).status, 201); assert.equal(f.count("multiplayer_rooms"), 1);
});
