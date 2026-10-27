import test from "node:test";
import assert from "node:assert/strict";
import { startDevServer } from "./dev-server.mjs";
import { POLICY } from "./room-api.mjs";

const avatar = { modelId: "SeoulResident_M01", bodyProfile: "standard", swimwear: false };
const pose = (id, kind = "npc", point = [10, 1, 20]) => ({ id, kind, position: point, rotation: [0, 0, 0], velocity: [0, 0, 0], motion: kind === "vehicle" ? "ai" : "walk" });
const action = (type, entityId, requestId = crypto.randomUUID()) => ({ requestId, type, entityId });
async function fixture(t, entities = [pose("car:0", "vehicle"), pose("car:1", "vehicle"), pose("npc:0"), pose("dog:0", "dog"), pose("npc:far", "npc", [100, 1, 20])]) {
  let clock = 100_000;
  const host = await startDevServer({ apiOnly: true, port: 0, now: () => clock });
  t.after(async () => { host.server.closeAllConnections(); await host.close(); });
  const f = { host, advance(ms = POLICY.intervalMs) { clock += ms; }, now: () => clock };
  function client() {
    return { cookie: "", actor: null, sequence: 0, point: [10, 1, 20],
      async call(path, { method = "POST", body = {}, token = this.actor?.sessionToken, headers = {} } = {}) {
        const response = await fetch(host.origin + path, { method, headers: { origin: host.origin, ...(method === "POST" ? { "content-type": "application/json" } : {}), ...(this.cookie ? { cookie: this.cookie } : {}), ...(token ? { authorization: "Bearer " + token } : {}), ...headers }, ...(method === "POST" ? { body: JSON.stringify(body) } : {}) });
        if (response.headers.get("set-cookie")) this.cookie = response.headers.get("set-cookie").split(";", 1)[0];
        return { status: response.status, body: await response.json() };
      },
      async sync(extra = {}) {
        const result = await this.call(`/api/multiplayer/rooms/${f.room.room.id}/players/${this.actor.selfId}/sync`, { body: { sequence: ++this.sequence, position: this.point, yaw: 0, motion: "idle", ...extra } });
        if (result.status === 200) this.point = result.body.players.find(p => p.id === this.actor.selfId).position;
        return result;
      },
      leave() { return this.call(`/api/multiplayer/rooms/${f.room.room.id}/players/${this.actor.selfId}/leave`); },
    };
  }
  f.owner = client(); f.guest = client();
  for (const c of [f.owner, f.guest]) assert.equal((await c.call("/api/multiplayer/dev-session")).status, 200);
  const created = await f.owner.call("/api/multiplayer/rooms", { body: { buildId: "sim2seoul-shared-world-v2", avatar, position: [10, 1, 20], yaw: 0, ...(entities === null ? {} : { world: { entities } }) } });
  assert.equal(created.status, 201); f.room = created.body; f.owner.actor = f.room;
  const joined = await f.guest.call(`/api/multiplayer/rooms/${f.room.room.id}/join`, { body: { invite: f.room.invite, buildId: "sim2seoul-shared-world-v2", avatar } });
  assert.equal(joined.status, 201); f.guest.actor = joined.body;
  return f;
}
const entity = (result, id) => result.body.world.entities.find(item => item.id === id);
const resultFor = (result, requestId) => result.body.world.actionResults.findLast(item => item.requestId === requestId);

test("legacy presence rooms omit world and retain ordinary owner-leave behavior", async t => {
  const f = await fixture(t, null); assert.equal("world" in f.room, false);
  assert.equal((await f.owner.leave()).status, 200); f.advance();
  const seen = await f.guest.sync(); assert.equal(seen.status, 200); assert.equal("world" in seen.body, false);
});
test("world snapshots bind host, catalog, public activity and exclude internal receipts", async t => {
  const f = await fixture(t); assert.equal(f.room.world.hostId, f.owner.actor.selfId); assert.equal(f.room.world.version, 1);
  assert.deepEqual(f.room.players[0].activity, { kind: "walk" });
  const text = JSON.stringify(f.room.world);
  for (const key of ["_commit", "_poseAtMs", "_released", "request_hash", "token_hash", "sessionToken"]) assert.equal(text.includes(key), false);
  f.advance(); const denied = await f.guest.sync({ world: { sequence: 1, entities: [pose("npc:0")] } });
  assert.equal(denied.status, 403); assert.equal(denied.body.error, "world_host_required");
});
test("two real HTTP clients race one car: exactly one claim, denial is a normal snapshot", async t => {
  const f = await fixture(t); f.advance(); const a = action("vehicle_enter", "car:0"), b = action("vehicle_enter", "car:0");
  const replies = await Promise.all([f.owner.sync({ actions: [a] }), f.guest.sync({ actions: [b] })]);
  assert.ok(replies.every(r => r.status === 200));
  const results = replies.map((r, i) => resultFor(r, [a, b][i].requestId));
  assert.equal(results.filter(r => r.ok).length, 1); assert.equal(results.filter(r => r.error === "vehicle_occupied").length, 1);
  const stored = JSON.parse(f.host.DB.sqlite.prepare("SELECT state_json FROM multiplayer_worlds").get().state_json);
  assert.ok([f.owner.actor.selfId, f.guest.actor.selfId].includes(stored.entities[0].driverId));
});
test("exclusive per-person lease, drive authority, stale epoch/sequence and parked release", async t => {
  const f = await fixture(t); f.advance();
  const entered = await f.guest.sync({ actions: [action("vehicle_enter", "car:0")] });
  const epoch = entity(entered, "car:0").leaseEpoch; assert.equal(epoch, 1);
  f.advance(); const second = action("vehicle_enter", "car:1"), denied = await f.guest.sync({ actions: [second] });
  assert.equal(resultFor(denied, second.requestId).error, "already_driving");
  f.advance(); const forged = await f.owner.sync({ drive: { entityId: "car:0", leaseEpoch: epoch, sequence: 1, position: [11, 1, 20], rotation: [0, 0, 0], velocity: [1, 0, 0] } });
  assert.equal(forged.status, 409);
  const driven = await f.guest.sync({ drive: { entityId: "car:0", leaseEpoch: epoch, sequence: 1, position: [40, 1, 20], rotation: [0, 0, 0], velocity: [60, 0, 0] } });
  assert.equal(driven.status, 200); assert.deepEqual(driven.body.players.find(p => p.id === f.guest.actor.selfId).position, [40, 1, 20]);
  assert.deepEqual(driven.body.players.find(p => p.id === f.guest.actor.selfId).activity, { kind: "vehicle", entityId: "car:0" });
  f.advance(); assert.equal((await f.guest.sync({ drive: { entityId: "car:0", leaseEpoch: epoch, sequence: 1, position: [40, 1, 20], rotation: [0, 0, 0], velocity: [0, 0, 0] } })).status, 409);
  const exited = await f.guest.sync({ actions: [action("vehicle_exit", "car:0")] });
  assert.equal(entity(exited, "car:0").mode, "parked"); assert.equal(entity(exited, "car:0").driverId, ""); assert.equal(entity(exited, "car:0").leaseEpoch, 2);
  f.advance(); const host = await f.owner.sync({ world: { sequence: 1, entities: [pose("car:0", "vehicle")] } });
  assert.deepEqual(entity(host, "car:0").position, [40, 1, 20]);
  const stale = await f.guest.sync({ drive: { entityId: "car:0", leaseEpoch: epoch, sequence: 2, position: [41, 1, 20], rotation: [0, 0, 0], velocity: [1, 0, 0] } });
  assert.equal(stale.status, 409);
});
test("host cannot overwrite leased vehicle; catalog and movement envelopes remain fixed", async t => {
  const f = await fixture(t); f.advance(); await f.guest.sync({ actions: [action("vehicle_enter", "car:0")] });
  const host = await f.owner.sync({ world: { sequence: 1, entities: [pose("car:0", "vehicle", [20, 1, 20]), pose("npc:0", "npc", [11, 1, 20])] } });
  assert.equal(host.status, 200); assert.deepEqual(entity(host, "car:0").position, [10, 1, 20]);
  f.advance(); assert.equal((await f.owner.sync({ world: { sequence: 1, entities: [] } })).status, 409);
  assert.equal((await f.owner.sync({ world: { sequence: 2, entities: [pose("new:arbitrary")] } })).status, 400);
  assert.equal((await f.owner.sync({ world: { sequence: 2, entities: [pose("npc:0", "vehicle")] } })).status, 400);
  const jump = await f.owner.sync({ world: { sequence: 2, entities: [pose("npc:0", "npc", [100, 1, 20])] } });
  assert.equal(jump.status, 422); assert.equal(jump.body.entityId, "npc:0"); assert.equal(jump.body.kind, "npc");
  assert.ok(jump.body.observedDistance > jump.body.allowedDistance); assert.equal(jump.body.elapsedMs, POLICY.intervalMs);
  assert.equal(Object.keys(jump.body).some(key => /token|cookie|user|invite/i.test(key)), false);
  assert.equal((await f.owner.sync({ world: { sequence: 2, entities: [{ ...pose("npc:0"), velocity: [25, 0, 0] }] } })).status, 400);
});
test("NPC/dog approvals enforce distance/kind, replay exactly once and retain receipt conflicts", async t => {
  const f = await fixture(t); f.advance(); const hit = action("npc_hit", "npc:0");
  const first = await f.guest.sync({ actions: [hit] }); assert.equal(resultFor(first, hit.requestId).ok, true);
  const until = entity(first, "npc:0").reactionUntilMs; assert.equal(entity(first, "npc:0").reactorId, f.guest.actor.selfId);
  f.advance(1500); const replay = await f.guest.sync({ actions: [hit] }); assert.equal(resultFor(replay, hit.requestId).ok, true);
  assert.equal(entity(replay, "npc:0").reactionUntilMs, 0); assert.ok(until < f.now());
  f.advance(); const conflict = await f.guest.sync({ actions: [{ ...hit, type: "npc_shove" }] }); assert.equal(resultFor(conflict, hit.requestId).error, "request_id_conflict");
  f.advance(); const far = action("npc_greet", "npc:far"), petNpc = action("npc_pet", "npc:0"), petDog = action("npc_pet", "dog:0");
  const actions = await f.guest.sync({ actions: [far, petNpc, petDog] });
  assert.equal(resultFor(actions, far.requestId).error, "interaction_out_of_range"); assert.equal(resultFor(actions, petNpc.requestId).error, "entity_kind_mismatch"); assert.equal(resultFor(actions, petDog.requestId).ok, true);
  assert.equal(f.host.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_world_actions WHERE player_id = ? AND request_id = ?").get(f.guest.actor.selfId, hit.requestId).n, 1);
});
test("enter proximity and off-foot NPC restrictions produce action denials", async t => {
  const f = await fixture(t, [pose("car:far", "vehicle", [100, 1, 20]), pose("car:near", "vehicle"), pose("npc:0")]); f.advance();
  const far = action("vehicle_enter", "car:far"), near = action("vehicle_enter", "car:near"), greet = action("npc_greet", "npc:0");
  const r = await f.guest.sync({ actions: [far, near, greet] }); assert.equal(r.status, 200);
  assert.equal(resultFor(r, far.requestId).error, "interaction_out_of_range"); assert.equal(resultFor(r, near.requestId).ok, true); assert.equal(resultFor(r, greet.requestId).error, "on_foot_required");
});
test("guest leave, TTL and token-rotating rejoin release old leases", async t => {
  const f = await fixture(t); f.advance(); await f.guest.sync({ actions: [action("vehicle_enter", "car:0")] });
  const old = f.guest.actor;
  const joined = await f.guest.call(`/api/multiplayer/rooms/${f.room.room.id}/join`, { body: { invite: f.room.invite, buildId: "sim2seoul-shared-world-v2", avatar } });
  // Join cooldown is one second after the first admission.
  assert.equal(joined.status, 429); f.advance();
  const rotated = await f.guest.call(`/api/multiplayer/rooms/${f.room.room.id}/join`, { body: { invite: f.room.invite, buildId: "sim2seoul-shared-world-v2", avatar } });
  assert.equal(rotated.status, 201); f.guest.actor = rotated.body; f.guest.sequence = 0;
  assert.equal(entity(rotated, "car:0").driverId, "");
  assert.equal((await f.guest.call(`/api/multiplayer/rooms/${f.room.room.id}/players/${old.selfId}/sync`, { token: old.sessionToken, body: { sequence: 2, position: [10, 1, 20], yaw: 0, motion: "idle" } })).status, 401);
  f.advance(); await f.guest.sync({ actions: [action("vehicle_enter", "car:0")] });
  assert.equal((await f.guest.leave()).status, 200); const seen = await f.owner.sync(); assert.equal(entity(seen, "car:0").mode, "parked");
});
test("silent guest lease expires while a live host keeps room; host loss closes world coherently", async t => {
  const f = await fixture(t); f.advance(); await f.guest.sync({ actions: [action("vehicle_enter", "car:0")] });
  f.advance(10_000); assert.equal((await f.owner.sync()).status, 200); f.advance(5500);
  const released = await f.owner.sync(); assert.equal(released.status, 200); assert.equal(entity(released, "car:0").driverId, "");
  f.advance(POLICY.presenceTtlMs); assert.equal((await f.owner.sync()).status, 404);
  assert.equal(f.host.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_worlds").get().n, 0);
  assert.equal(f.host.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_world_actions").get().n, 0);
});
test("explicit host leave and owner rejoin close world rooms and revoke every actor", async t => {
  const f = await fixture(t); assert.equal((await f.owner.leave()).body.closed, true); f.advance(); assert.equal((await f.guest.sync()).status, 404);
  const g = await fixture(t); g.advance(1000);
  const rejoin = await g.owner.call(`/api/multiplayer/rooms/${g.room.room.id}/join`, { body: { invite: g.room.invite, buildId: "sim2seoul-shared-world-v2", avatar } });
  assert.equal(rejoin.status, 404); assert.equal((await g.guest.sync()).status, 404);
});
test("world bounds, 96 entities, four actions, private data and identity binding are enforced", async t => {
  const f = await fixture(t, Array.from({ length: 96 }, (_, i) => pose("npc:" + i))); f.advance();
  assert.equal(f.room.world.entities.length, 96);
  assert.equal((await f.owner.sync({ actions: Array.from({ length: 5 }, () => action("npc_hit", "npc:0")) })).status, 400);
  assert.equal((await f.owner.sync({ actions: [{ requestId: crypto.randomUUID(), type: "npc_hit", entityId: 123 }] })).status, 400);
  assert.equal((await f.guest.call(`/api/multiplayer/rooms/${f.room.room.id}/players/${f.owner.actor.selfId}/sync`, { token: f.owner.actor.sessionToken, headers: { "oai-authenticated-user-id": "forged-owner" }, body: { sequence: 1, position: [10, 1, 20], yaw: 0, motion: "idle" } })).status, 401);
  f.advance(5000);
  for (const entities of [Array.from({ length: 97 }, (_, i) => pose("npc:" + i)), [pose("../private")], [{ ...pose("npc:nan"), position: [null, 1, 2] }]]) {
    const r = await f.owner.call("/api/multiplayer/rooms", { body: { buildId: "sim2seoul-shared-world-v2", avatar, position: [10, 1, 20], yaw: 0, world: { entities } } }); assert.equal(r.status, 400); f.advance(5000);
  }
});
test("interaction lag allowance uses only a recent server-approved previous pose", async t => {
  const f = await fixture(t, [pose("npc:recent"), pose("npc:late")]); f.advance();
  assert.equal((await f.owner.sync({ world: { sequence: 1, entities: [pose("npc:recent", "npc", [20, 1, 20]), pose("npc:late", "npc", [20, 1, 20])] } })).status, 200);
  const recent = action("npc_greet", "npc:recent"), accepted = await f.guest.sync({ actions: [recent] });
  assert.equal(resultFor(accepted, recent.requestId).ok, true);
  assert.equal(JSON.stringify(accepted.body.world).includes("_previous"), false);
  f.advance(1501); const late = action("npc_greet", "npc:late"), rejected = await f.guest.sync({ actions: [late] });
  assert.equal(resultFor(rejected, late.requestId).error, "interaction_out_of_range");
  for (const [delay, expected] of [[0, true], [1501, false]]) {
    const g = await fixture(t, [pose("car:0", "vehicle")]); g.advance();
    await g.owner.sync({ world: { sequence: 1, entities: [pose("car:0", "vehicle", [30, 1, 20])] } });
    g.advance(delay); const enter = action("vehicle_enter", "car:0"), reply = await g.guest.sync({ actions: [enter] });
    assert.equal(resultFor(reply, enter.requestId).ok, expected);
    if (!expected) assert.equal(resultFor(reply, enter.requestId).error, "interaction_out_of_range");
  }
});
test("receipts prevent old effects after the public 32-result ring is pruned", async t => {
  const f = await fixture(t, [pose("npc:0")]); const first = action("npc_hit", "npc:0");
  for (let i = 0; i < 34; i += 1) {
    f.advance(); if (i % 10 === 0) assert.equal((await f.owner.sync()).status, 200);
    assert.equal((await f.guest.sync({ actions: [i === 0 ? first : action("npc_greet", "npc:0")] })).status, 200);
  }
  f.advance(2500); const replay = await f.guest.sync({ actions: [first] });
  assert.equal(replay.status, 200); assert.equal(replay.body.world.actionResults.length, 32);
  assert.equal(resultFor(replay, first.requestId).ok, true); assert.equal(entity(replay, "npc:0").reactionUntilMs, 0);
  assert.equal(f.host.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_world_actions").get().n, 34);
});
test("host timeout closes the world even when the guest remains live", async t => {
  const f = await fixture(t); f.advance(10_000); assert.equal((await f.guest.sync()).status, 200);
  f.advance(5500); assert.equal((await f.guest.sync()).status, 404);
  assert.equal(f.host.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_players").get().n, 0);
});

test("owner drives with 44 live authority entities and exits back to on-foot sync", async t => {
  const catalog = [
    ...Array.from({ length: 14 }, (_, i) => pose("car:" + i, "vehicle", [10, 1, 20 + i * 6])),
    ...Array.from({ length: 28 }, (_, i) => pose("npc:" + i, "npc", [10 + i, 1, 20])),
    ...Array.from({ length: 2 }, (_, i) => pose("dog:" + i, "dog", [12 + i, 1, 21])),
  ];
  const f = await fixture(t, catalog); let seconds = 0, worldSequence = 0;
  const authority = carPoint => ({ sequence: ++worldSequence, entities: catalog.map(row => ({ ...row,
    position: row.id === "car:0" ? carPoint : [row.position[0] + (row.kind === "vehicle" ? 0 : seconds * 1.5), 1, row.position[2] + (row.kind === "vehicle" ? seconds * 5 : 0)],
    velocity: row.kind === "vehicle" ? [0, 0, 5] : [1.5, 0, 0], motion: row.id === "car:0" ? "parked" : row.motion,
  })) });
  f.advance(550); seconds += .55;
  const entered = await f.owner.sync({ world: authority([10, 1, 20]), actions: [action("vehicle_enter", "car:0")] });
  assert.equal(entered.status, 200); const epoch = entity(entered, "car:0").leaseEpoch;
  let metres = 0, driveSequence = 0;
  for (const ms of [550, 550, 500]) {
    f.advance(ms); seconds += ms / 1000; metres += (43 / 3.6) * ms / 1000;
    const point = [10 + metres, 1, 20];
    const driven = await f.owner.sync({ position: [point[0] - .42, .8, 19.9], world: authority(point), drive: { entityId: "car:0", leaseEpoch: epoch, sequence: ++driveSequence, position: point, rotation: [0, 0, 0], velocity: [43 / 3.6, 0, 0] } });
    assert.equal(driven.status, 200); assert.equal(driven.body.world.entities.length, 44);
    assert.deepEqual(driven.body.players.find(row => row.id === f.owner.actor.selfId).activity, { kind: "vehicle", entityId: "car:0" });
    assert.deepEqual(entity(driven, "car:0").position, point.map(x => Math.round(x * 1000) / 1000));
  }
  f.advance(550); seconds += .55; const finalPoint = [10 + metres, 1, 20];
  const exited = await f.owner.sync({ world: authority(finalPoint), drive: { entityId: "car:0", leaseEpoch: epoch, sequence: ++driveSequence, position: finalPoint, rotation: [0, 0, 0], velocity: [0, 0, 0] }, actions: [action("vehicle_exit", "car:0")] });
  assert.equal(exited.status, 200); assert.equal(entity(exited, "car:0").mode, "parked");
  assert.deepEqual(exited.body.players.find(row => row.id === f.owner.actor.selfId).activity, { kind: "walk" });
  f.advance(550); seconds += .55; const footPoint = [finalPoint[0] - 1.85, 1, finalPoint[2] - .35];
  const walking = await f.owner.sync({ position: footPoint, world: authority(finalPoint) });
  assert.equal(walking.status, 200); assert.equal(walking.body.world.hostId, f.owner.actor.selfId);
  assert.deepEqual(walking.body.players.find(row => row.id === f.owner.actor.selfId).activity, { kind: "walk" });
  assert.equal(entity(walking, "npc:0").position[0], Math.round((10 + seconds * 1.5) * 1000) / 1000);
  assert.deepEqual(entity(walking, "car:0").position, finalPoint.map(x => Math.round(x * 1000) / 1000));
});

test("a rejected live NPC pose atomically preserves an owner's drive lease and exit request", async t => {
  const f = await fixture(t, [pose("car:0", "vehicle"), pose("npc:0")]); f.advance();
  const entered = await f.owner.sync({ world: { sequence: 1, entities: [pose("car:0", "vehicle"), pose("npc:0")] }, actions: [action("vehicle_enter", "car:0")] });
  const epoch = entity(entered, "car:0").leaseEpoch; f.advance();
  const exit = action("vehicle_exit", "car:0");
  const rejected = await f.owner.sync({ world: { sequence: 2, entities: [pose("car:0", "vehicle", [15, 1, 20]), pose("npc:0", "npc", [100, 1, 20])] }, drive: { entityId: "car:0", leaseEpoch: epoch, sequence: 1, position: [15, 1, 20], rotation: [0, 0, 0], velocity: [10, 0, 0] }, actions: [exit] });
  assert.equal(rejected.status, 422); assert.equal(rejected.body.error, "world_movement_out_of_range"); assert.equal(rejected.body.entityId, "npc:0");
  const stored = JSON.parse(f.host.DB.sqlite.prepare("SELECT state_json FROM multiplayer_worlds").get().state_json);
  assert.equal(stored.sequence, 1); assert.equal(stored.entities[0].driverId, f.owner.actor.selfId);
  assert.equal(stored.entities[0].leaseEpoch, epoch); assert.deepEqual(stored.entities[0].position, [10, 1, 20]);
  assert.equal(f.host.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM multiplayer_world_actions WHERE request_id = ?").get(exit.requestId).n, 0);
  const retried = await f.owner.sync({ world: { sequence: 2, entities: [pose("car:0", "vehicle", [15, 1, 20]), pose("npc:0", "npc", [10.5, 1, 20])] }, drive: { entityId: "car:0", leaseEpoch: epoch, sequence: 1, position: [15, 1, 20], rotation: [0, 0, 0], velocity: [10, 0, 0] }, actions: [exit] });
  assert.equal(retried.status, 200); assert.equal(resultFor(retried, exit.requestId).ok, true);
  assert.equal(entity(retried, "car:0").mode, "parked");
});
