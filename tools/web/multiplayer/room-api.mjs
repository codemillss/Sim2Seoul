/**
 * Bounded Sites/D1 HTTP presence and shared-world protocol.
 * Call createRoomApi()(request, env) behind Sites authenticated dispatch only.
 * Development hosts derive identity from validated local sessions and strip
 * untrusted identity headers; clients cannot supply production identities.
 * It returns null outside /api/multiplayer/ so a host can serve its other routes.
 */
export const POLICY = Object.freeze({
  protocol: "sim2seoul-presence-v1",
  capacity: 8, // Admission policy, NOT a measured concurrency capacity.
  activeRoomsPerOwner: 2,
  createCooldownMs: 5000,
  joinCooldownMs: 1000,
  roomLifetimeMs: 30 * 60 * 1000,
  presenceTtlMs: 15 * 1000,
  intervalMs: 500, // One combined update/snapshot per 500 ms, at most 2 Hz.
  idleHeartbeatMs: 5000,
  interpolationMs: 600,
  maximumBodyBytes: 48 * 1024,
  maximumHorizontalMps: 24, // Includes the existing 21 m/s on-foot turbo profile.
  maximumVerticalMps: 50,
  maximumMovementCreditMs: 2000,
});

const PREFIX = "/api/multiplayer/";
const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const ROOM_ROUTE = new RegExp(`^${PREFIX}rooms/(${UUID})/(join|close|players/(${UUID})/(sync|snapshot|leave))$`);
const MODELS = new Set(["SeoulResident_M01", "SeoulResident_F01"]);
const PROFILES = new Set(["standard", "soft", "athletic"]);
const MOTIONS = new Set(["idle", "walk", "run", "jump", "swim"]);
const WORLD_MOTIONS = new Set(["ai", "parked", "idle", "walk", "run"]);
const WORLD_ACTIONS = new Set(["vehicle_enter", "vehicle_exit", "npc_greet", "npc_pet", "npc_shove", "npc_hit"]);
const ENTITY_ID = /^[A-Za-z0-9:_-]{1,96}$/;
const REQUEST_ID = new RegExp(`^${UUID}$`);

class HttpError extends Error {
  constructor(status, code, details = {}) {
    super(code);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

function reply(value, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...extraHeaders,
    },
  });
}

async function hash(value) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map(value => value.toString(16).padStart(2, "0")).join("");
}

function token(bytes = 24) {
  return [...crypto.getRandomValues(new Uint8Array(bytes))]
    .map(value => value.toString(16).padStart(2, "0")).join("");
}

function identity(request) {
  // These headers are trusted ONLY when injected by Sites dispatch. Never expose
  // this module as an unprotected standalone server that trusts browser headers.
  const value = request.headers.get("oai-authenticated-user-id");
  if (!value || value.length > 256) throw new HttpError(401, "sign_in_required");
  return value;
}

function originGuard(request, url) {
  const origin = request.headers.get("origin");
  if ((origin && origin !== url.origin) || (request.method === "POST" && !origin)) {
    throw new HttpError(403, "same_origin_required");
  }
}

async function bodyJson(request) {
  if (request.headers.get("content-type")?.split(";", 1)[0] !== "application/json") {
    throw new HttpError(415, "json_required");
  }
  if (Number(request.headers.get("content-length")) > POLICY.maximumBodyBytes) {
    throw new HttpError(413, "body_too_large");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, "json_required");
  const parts = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > POLICY.maximumBodyBytes) {
      await reader.cancel();
      throw new HttpError(413, "body_too_large");
    }
    parts.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) { bytes.set(part, offset); offset += part.byteLength; }
  let result;
  try { result = JSON.parse(new TextDecoder().decode(bytes)); }
  catch { throw new HttpError(400, "invalid_json"); }
  if (!result || Array.isArray(result) || typeof result !== "object") {
    throw new HttpError(400, "object_required");
  }
  if (length > 2048 && result.world === undefined && result.actions === undefined && result.drive === undefined) throw new HttpError(413, "body_too_large");
  return result;
}

function exactKeys(value, allowed) {
  if (Object.keys(value).some(key => !allowed.includes(key))) throw new HttpError(400, "unknown_field");
}

function buildId(value) {
  if (typeof value !== "string" || !/^[a-zA-Z0-9._-]{8,80}$/.test(value)) {
    throw new HttpError(400, "invalid_build_id");
  }
  return value;
}

function avatar(value) {
  if (!value || Array.isArray(value) || typeof value !== "object") throw new HttpError(400, "invalid_avatar");
  exactKeys(value, ["modelId", "bodyProfile", "swimwear"]);
  if (!MODELS.has(value.modelId) || !PROFILES.has(value.bodyProfile) || typeof value.swimwear !== "boolean") {
    throw new HttpError(400, "invalid_avatar");
  }
  return { modelId: value.modelId, bodyProfile: value.bodyProfile, swimwear: value.swimwear };
}

function position(value) {
  if (!Array.isArray(value) || value.length !== 3 || value.some(x => typeof x !== "number" || !Number.isFinite(x))) {
    throw new HttpError(400, "invalid_position");
  }
  // Coarse protocol envelope, NOT the actual city collision or walking boundary.
  if (Math.abs(value[0]) > 1000 || value[1] < -100 || value[1] > 500 || Math.abs(value[2]) > 1000) {
    throw new HttpError(422, "position_outside_envelope");
  }
  return value.map(x => Math.round(x * 1000) / 1000);
}

function yaw(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || Math.abs(value) > Math.PI) {
    throw new HttpError(400, "invalid_yaw");
  }
  // Keep validated endpoints inside the same envelope on snapshot round trips:
  // rounding Math.PI to four decimals would produce 3.1416 > Math.PI.
  return value;
}

function publicPlayer(row) {
  return {
    id: row.id,
    avatar: JSON.parse(row.avatar_json),
    sequence: row.sequence,
    position: [row.x, row.y, row.z],
    yaw: row.yaw,
    motion: row.motion,
    updatedAtMs: row.last_position_ms,
  };
}

function vector(value, limit, code) {
  if (!Array.isArray(value) || value.length !== 3 || value.some(x => typeof x !== "number" || !Number.isFinite(x) || Math.abs(x) > limit)) throw new HttpError(400, code);
  return [...value];
}
function entityPose(value) {
  if (!value || Array.isArray(value) || typeof value !== "object") throw new HttpError(400, "invalid_world_entity");
  exactKeys(value, ["id", "kind", "position", "rotation", "velocity", "motion"]);
  if (typeof value.id !== "string" || !ENTITY_ID.test(value.id) || !["vehicle", "npc", "dog"].includes(value.kind) || !WORLD_MOTIONS.has(value.motion)) throw new HttpError(400, "invalid_world_entity");
  const velocity = vector(value.velocity, value.kind === "vehicle" ? 80 : 24, "invalid_world_velocity");
  if (Math.hypot(...velocity) > (value.kind === "vehicle" ? 80 : 24)) throw new HttpError(422, "world_speed_out_of_range");
  return { id: value.id, kind: value.kind, position: position(value.position), rotation: vector(value.rotation, Math.PI, "invalid_world_rotation"), velocity, motion: value.motion };
}
function worldEntities(value) {
  if (!Array.isArray(value) || value.length > 96) throw new HttpError(400, "invalid_world_entities");
  const entities = value.map(entityPose);
  if (new Set(entities.map(entity => entity.id)).size !== entities.length) throw new HttpError(400, "duplicate_world_entity");
  return entities;
}
function initialWorld(value, hostId, nowMs) {
  if (!value || Array.isArray(value) || typeof value !== "object") throw new HttpError(400, "invalid_world");
  exactKeys(value, ["entities"]);
  return { version: 1, hostId, sequence: 0, updatedAtMs: nowMs, actionResults: [], entities: worldEntities(value.entities).map(entity => ({
    ...entity, driverId: "", leaseEpoch: 0, mode: entity.kind === "vehicle" && entity.motion !== "ai" ? "parked" : "ai",
    reactionKind: "", reactionUntilMs: 0, reactorId: "", _poseAtMs: nowMs, _driveSequence: 0, _released: false,
  })) };
}
function publicWorld(state) {
  return { version: 1, hostId: state.hostId, sequence: state.sequence, updatedAtMs: state.updatedAtMs,
    entities: state.entities.map(entity => Object.fromEntries(Object.entries(entity).filter(([key]) => !key.startsWith("_")))), actionResults: state.actionResults };
}
function stopVehicle(entity) {
  entity.driverId = ""; entity.leaseEpoch += 1; entity.mode = "parked"; entity.motion = "parked";
  entity.velocity = [0, 0, 0]; entity._driveSequence = 0; entity._released = true;
}
function releaseWorldPlayer(state, playerId) {
  for (const entity of state.entities) if (entity.kind === "vehicle" && entity.driverId === playerId) stopVehicle(entity);
}
function worldActivity(state, playerId) {
  const vehicle = state.entities.find(entity => entity.kind === "vehicle" && entity.driverId === playerId);
  return vehicle ? { kind: "vehicle", entityId: vehicle.id } : { kind: "walk" };
}
function moveEntity(entity, pose, nowMs) {
  const elapsed = Math.min(Math.max(0, nowMs - entity._poseAtMs), POLICY.maximumMovementCreditMs) / 1000;
  const speed = entity.kind === "vehicle" ? 80 : 24;
  const observedDistance = Math.hypot(...pose.position.map((x, index) => x - entity.position[index]));
  const allowedDistance = speed * elapsed + .25;
  if (observedDistance > allowedDistance) throw new HttpError(422, "world_movement_out_of_range", { entityId: entity.id, kind: entity.kind, observedDistance, allowedDistance, elapsedMs: nowMs - entity._poseAtMs });
  entity._previousPosition = [...entity.position]; entity._previousAtMs = entity._poseAtMs;
  for (const key of ["position", "rotation", "velocity", "motion"]) entity[key] = pose[key];
  entity._poseAtMs = nowMs;
}
function withinInteractionRange(entity, playerPosition, distance, nowMs) {
  const near = point => Math.hypot(...point.map((x, index) => x - playerPosition[index])) <= distance;
  // Rendering interpolates approved poses. Only the immediately preceding
  // server-approved pose is eligible, and only for a bounded 1.5-second window.
  return near(entity.position) || (entity._previousPosition && nowMs - entity._previousAtMs <= 1500 && near(entity._previousPosition));
}

async function transitionWorld(store, row, player, data, nowMs, activeIds, playerPosition) {
  const state = JSON.parse(row.state_json), receipts = [];
  for (const entity of state.entities) {
    if (entity.driverId && !activeIds.has(entity.driverId)) stopVehicle(entity);
    if (entity.reactionUntilMs <= nowMs) { entity.reactionKind = ""; entity.reactionUntilMs = 0; entity.reactorId = ""; }
  }
  if (data.world !== undefined) {
    if (player.id !== state.hostId) throw new HttpError(403, "world_host_required");
    const update = data.world;
    if (!update || Array.isArray(update) || typeof update !== "object") throw new HttpError(400, "invalid_world_update");
    exactKeys(update, ["sequence", "entities"]);
    if (!Number.isSafeInteger(update.sequence) || update.sequence <= state.sequence || update.sequence > 2147483647) throw new HttpError(409, "world_sequence_stale");
    for (const pose of worldEntities(update.entities)) {
      const entity = state.entities.find(item => item.id === pose.id);
      if (!entity || entity.kind !== pose.kind) throw new HttpError(400, "world_catalog_mismatch");
      if (entity.kind === "vehicle" && (entity.driverId || entity._released)) continue;
      moveEntity(entity, pose, nowMs);
    }
    state.sequence = update.sequence;
  }
  if (data.drive !== undefined) {
    const drive = data.drive;
    if (!drive || Array.isArray(drive) || typeof drive !== "object") throw new HttpError(400, "invalid_drive");
    exactKeys(drive, ["entityId", "leaseEpoch", "sequence", "position", "rotation", "velocity"]);
    const entity = state.entities.find(item => item.id === drive.entityId && item.kind === "vehicle");
    if (!entity || entity.driverId !== player.id || drive.leaseEpoch !== entity.leaseEpoch) throw new HttpError(409, "vehicle_lease_invalid");
    if (!Number.isSafeInteger(drive.sequence) || drive.sequence <= entity._driveSequence || drive.sequence > 2147483647) throw new HttpError(409, "drive_sequence_stale");
    const velocity = vector(drive.velocity, 80, "invalid_world_velocity");
    const pose = entityPose({ id: entity.id, kind: "vehicle", position: drive.position, rotation: drive.rotation, velocity, motion: Math.hypot(...velocity) > .1 ? "run" : "idle" });
    moveEntity(entity, pose, nowMs); entity._driveSequence = drive.sequence;
    playerPosition = [...entity.position];
  }
  const actions = data.actions ?? [];
  if (!Array.isArray(actions) || actions.length > 4) throw new HttpError(400, "invalid_actions");
  const inPacket = new Map();
  for (const action of actions) {
    if (!action || Array.isArray(action) || typeof action !== "object") throw new HttpError(400, "invalid_action");
    exactKeys(action, ["requestId", "type", "entityId"]);
    if (typeof action.requestId !== "string" || !REQUEST_ID.test(action.requestId) || !WORLD_ACTIONS.has(action.type) || typeof action.entityId !== "string" || !ENTITY_ID.test(action.entityId)) throw new HttpError(400, "invalid_action");
    const requestHash = await hash(JSON.stringify({ type: action.type, entityId: action.entityId }));
    const previous = inPacket.get(action.requestId) ?? await store.stmt("SELECT request_hash, result_json FROM multiplayer_world_actions WHERE room_id = ? AND player_id = ? AND request_id = ?", row.room_id, player.id, action.requestId).first();
    if (previous) {
      if (previous.request_hash !== requestHash) state.actionResults.push({ playerId: player.id, ...action, ok: false, error: "request_id_conflict" });
      else {
        // A replayed receipt is visible again without reapplying its effect.
        state.actionResults = state.actionResults.filter(item => item.playerId !== player.id || item.requestId !== action.requestId);
        state.actionResults.push(JSON.parse(previous.result_json));
      }
      continue;
    }
    const result = { playerId: player.id, ...action, ok: false, error: "" };
    const entity = state.entities.find(item => item.id === action.entityId);
    if (!entity) result.error = "entity_unavailable";
    else if (action.type === "vehicle_enter") {
      if (entity.kind !== "vehicle") result.error = "entity_kind_mismatch";
      else if (entity.driverId) result.error = entity.driverId === player.id ? "already_driving" : "vehicle_occupied";
      else if (worldActivity(state, player.id).kind === "vehicle") result.error = "already_driving";
      else if (!withinInteractionRange(entity, playerPosition, 5, nowMs)) result.error = "interaction_out_of_range";
      else { entity.driverId = player.id; entity.leaseEpoch += 1; entity.mode = "driven"; entity._driveSequence = 0; entity._poseAtMs = nowMs; result.ok = true; }
    } else if (action.type === "vehicle_exit") {
      if (entity.kind !== "vehicle" || entity.driverId !== player.id) result.error = "vehicle_driver_required";
      else { playerPosition = [...entity.position]; stopVehicle(entity); result.ok = true; }
    } else if (!["npc", "dog"].includes(entity.kind) || (action.type === "npc_pet" && entity.kind !== "dog")) result.error = "entity_kind_mismatch";
    else if (worldActivity(state, player.id).kind === "vehicle") result.error = "on_foot_required";
    else if (!withinInteractionRange(entity, playerPosition, 3, nowMs)) result.error = "interaction_out_of_range";
    else {
      entity.reactionKind = action.type.slice(4); entity.reactionUntilMs = nowMs + (["greet", "pet"].includes(entity.reactionKind) ? 2000 : 1000);
      entity.reactorId = player.id; result.ok = true;
    }
    state.actionResults.push(result);
    const receipt = { requestId: action.requestId, request_hash: requestHash, result_json: JSON.stringify(result) };
    receipts.push(receipt); inPacket.set(action.requestId, receipt);
  }
  state.actionResults = state.actionResults.slice(-32); state.updatedAtMs = nowMs; state._commit = crypto.randomUUID();
  const activity = worldActivity(state, player.id);
  if (activity.kind === "vehicle") playerPosition = [...state.entities.find(entity => entity.id === activity.entityId).position];
  return { state, receipts, position: playerPosition, activity };
}

class D1Rooms {
  constructor(db) {
    // Ordinary D1 binding operations go to the primary database. Do not change
    // this to unconstrained replicated reads: other players' motion may be stale.
    this.db = db;
  }
  stmt(sql, ...values) { return this.db.prepare(sql).bind(...values); }
  async reserve(userId, operation, nowMs, cooldownMs) {
    const result = await this.stmt(`INSERT INTO multiplayer_rate_limits (key, last_ms) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET last_ms = excluded.last_ms WHERE last_ms <= ?`,
      await hash(`${operation}:${userId}`), nowMs, nowMs - cooldownMs).run();
    if (result.meta.changes !== 1) throw new HttpError(429, "account_action_rate_limited", { retryAfterMs: cooldownMs });
  }
  async snapshot(room, nowMs) {
    const result = await this.stmt(
      `SELECT id, avatar_json, sequence, x, y, z, yaw, motion, last_position_ms
       FROM multiplayer_players WHERE room_id = ? AND last_seen_ms > ? ORDER BY id LIMIT ?`,
      room.id, nowMs - POLICY.presenceTtlMs, POLICY.capacity,
    ).all();
    const worldRow = await this.world(room.id);
    const world = worldRow ? JSON.parse(worldRow.state_json) : null;
    return {
      protocol: POLICY.protocol,
      serverNowMs: nowMs,
      room: { id: room.id, buildId: room.build_id, expiresAtMs: room.expires_ms, capacity: POLICY.capacity },
      transport: { type: "http-poll", intervalMs: POLICY.intervalMs, idleHeartbeatMs: POLICY.idleHeartbeatMs, interpolationMs: POLICY.interpolationMs },
      players: result.results.map(row => ({ ...publicPlayer(row), ...(world ? { activity: worldActivity(world, row.id) } : {}) })),
      ...(world ? { world: publicWorld(world) } : {}),
    };
  }
  async room(id, nowMs) {
    const room = await this.stmt("SELECT * FROM multiplayer_rooms WHERE id = ? AND expires_ms > ?", id, nowMs).first();
    if (!room) throw new HttpError(404, "room_unavailable");
    const world = await this.world(id);
    if (world && !await this.stmt("SELECT id FROM multiplayer_players WHERE id = ? AND room_id = ? AND last_seen_ms > ?", world.host_id, id, nowMs - POLICY.presenceTtlMs).first()) {
      await this.stmt("DELETE FROM multiplayer_rooms WHERE id = ? AND NOT EXISTS (SELECT 1 FROM multiplayer_players WHERE id = ? AND room_id = ? AND last_seen_ms > ?)", id, world.host_id, id, nowMs - POLICY.presenceTtlMs).run();
      throw new HttpError(404, "room_unavailable");
    }
    return room;
  }
  async world(roomId) { return this.stmt("SELECT * FROM multiplayer_worlds WHERE room_id = ?", roomId).first(); }
  worldWrite(row, state, player, nowMs) {
    return this.stmt(`UPDATE multiplayer_worlds SET revision = revision + 1, state_json = ?, updated_ms = ?
      WHERE room_id = ? AND revision = ? AND
      EXISTS (SELECT 1 FROM multiplayer_players WHERE id = ? AND room_id = ? AND token_hash = ? AND sequence = ? AND last_action_ms = ? AND last_seen_ms > ?) AND
      EXISTS (SELECT 1 FROM multiplayer_rooms WHERE id = ? AND expires_ms > ?) AND
      EXISTS (SELECT 1 FROM multiplayer_players WHERE id = ? AND room_id = ? AND last_seen_ms > ?)`,
      JSON.stringify(state), nowMs, row.room_id, row.revision, player.id, row.room_id, player.token_hash, player.sequence, player.last_action_ms,
      nowMs - POLICY.presenceTtlMs, row.room_id, nowMs, row.host_id, row.room_id, nowMs - POLICY.presenceTtlMs);
  }
  worldCommitExists(row, state) {
    return { sql: "EXISTS (SELECT 1 FROM multiplayer_worlds WHERE room_id = ? AND revision = ? AND state_json = ?)", values: [row.room_id, row.revision + 1, JSON.stringify(state)] };
  }
  async worldAction(room, row, player, operation, data, nowMs) {
    if (operation === "leave" && row.host_id === player.id) {
      await this.stmt("DELETE FROM multiplayer_rooms WHERE id = ? AND EXISTS (SELECT 1 FROM multiplayer_players WHERE id = ? AND token_hash = ?)", room.id, player.id, player.token_hash).run();
      return { left: true, closed: true };
    }
    const waitMs = POLICY.intervalMs - (nowMs - player.last_action_ms);
    if (operation !== "leave" && waitMs > 0) throw new HttpError(429, "update_rate_limited", { retryAfterMs: waitMs });
    if (operation === "sync" && data.sequence <= player.sequence) throw new HttpError(409, "sequence_stale");
    const state = JSON.parse(row.state_json);
    if (operation === "sync" && worldActivity(state, player.id).kind !== "vehicle") {
      const elapsed = Math.min(nowMs - player.last_position_ms, POLICY.maximumMovementCreditMs) / 1000;
      if (Math.hypot(data.position[0] - player.x, data.position[2] - player.z) > POLICY.maximumHorizontalMps * elapsed + .25 || Math.abs(data.position[1] - player.y) > POLICY.maximumVerticalMps * elapsed + .25) throw new HttpError(422, "movement_out_of_range", { acceptedPlayer: publicPlayer(player) });
    }
    const active = await this.stmt("SELECT id FROM multiplayer_players WHERE room_id = ? AND last_seen_ms > ?", room.id, nowMs - POLICY.presenceTtlMs).all();
    const next = await transitionWorld(this, row, player, data, nowMs, new Set(active.results.map(item => item.id)), operation === "sync" ? data.position : [player.x, player.y, player.z]);
    if (operation === "leave") releaseWorldPlayer(next.state, player.id);
    const committed = this.worldCommitExists(row, next.state);
    const statements = [this.worldWrite(row, next.state, player, nowMs)];
    if (operation === "leave") statements.push(this.stmt(`DELETE FROM multiplayer_players WHERE id = ? AND token_hash = ? AND ${committed.sql}`, player.id, player.token_hash, ...committed.values));
    else statements.push(this.stmt(`UPDATE multiplayer_players SET sequence = ?, x = ?, y = ?, z = ?, yaw = ?, motion = ?, avatar_json = ?, last_action_ms = ?, last_position_ms = ?, last_seen_ms = ? WHERE id = ? AND token_hash = ? AND ${committed.sql}`,
      operation === "sync" ? data.sequence : player.sequence, ...next.position, operation === "sync" ? data.yaw : player.yaw,
      next.activity.kind === "vehicle" ? "idle" : (data.motion ?? player.motion), JSON.stringify(data.avatar ?? JSON.parse(player.avatar_json)), nowMs,
      operation === "sync" ? nowMs : player.last_position_ms, nowMs, player.id, player.token_hash, ...committed.values));
    for (const receipt of next.receipts) statements.push(this.stmt(`INSERT INTO multiplayer_world_actions (room_id, player_id, request_id, request_hash, result_json, created_ms) SELECT ?, ?, ?, ?, ?, ? WHERE ${committed.sql}`,
      room.id, player.id, receipt.requestId, receipt.request_hash, receipt.result_json, nowMs, ...committed.values));
    const result = await this.db.batch(statements);
    if (result[0].meta.changes !== 1 || result[1].meta.changes !== 1) throw new HttpError(409, "concurrent_update_retry");
    return operation === "leave" ? { left: true } : { ...(await this.snapshot(room, nowMs)), selfId: player.id };
  }
  async create(userId, data, nowMs) {
    await this.reserve(userId, "create", nowMs, POLICY.createCooldownMs);
    const id = crypto.randomUUID();
    const playerId = crypto.randomUUID();
    const invite = token(16);
    const sessionToken = token();
    const ownerKey = await hash(`sites-user:${userId}`);
    const userKey = await hash(`${id}:${userId}`);
    const room = { id, build_id: data.buildId, expires_ms: nowMs + POLICY.roomLifetimeMs };
    const statements = [
      // Bounded opportunistic garbage collection; no request-time schema DDL.
      this.stmt("DELETE FROM multiplayer_rooms WHERE id IN (SELECT id FROM multiplayer_rooms WHERE expires_ms <= ? LIMIT 32)", nowMs),
      this.stmt("DELETE FROM multiplayer_rate_limits WHERE key IN (SELECT key FROM multiplayer_rate_limits WHERE last_ms < ? LIMIT 32)", nowMs - POLICY.roomLifetimeMs),
      // A closed tab has no reader to notice host TTL. Reclaim only this
      // owner's abandoned shared worlds in the same transaction as admission.
      this.stmt(`DELETE FROM multiplayer_rooms WHERE owner_key = ? AND id IN (
        SELECT r.id FROM multiplayer_rooms r JOIN multiplayer_worlds w ON w.room_id = r.id
        WHERE r.owner_key = ? AND NOT EXISTS (
          SELECT 1 FROM multiplayer_players p WHERE p.room_id = r.id AND p.id = w.host_id AND p.last_seen_ms > ?
        ) ORDER BY r.created_ms, r.id LIMIT 32)`, ownerKey, ownerKey, nowMs - POLICY.presenceTtlMs),
      this.stmt(`INSERT INTO multiplayer_rooms
        (id, owner_key, invite_hash, build_id, spawn_x, spawn_y, spawn_z, created_ms, expires_ms)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE
        (SELECT COUNT(*) FROM multiplayer_rooms WHERE owner_key = ? AND expires_ms > ?) < ?`,
        id, ownerKey, await hash(invite), data.buildId, ...data.position, nowMs, room.expires_ms,
        ownerKey, nowMs, POLICY.activeRoomsPerOwner),
      this.stmt(`INSERT INTO multiplayer_players
        (id, room_id, user_key, token_hash, avatar_json, x, y, z, yaw, last_action_ms, last_position_ms, last_seen_ms)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM multiplayer_rooms WHERE id = ?)`,
        playerId, id, userKey, await hash(sessionToken), JSON.stringify(data.avatar), ...data.position, data.yaw,
        nowMs, nowMs, nowMs, id),
    ];
    if (data.world !== undefined) statements.push(this.stmt(`INSERT INTO multiplayer_worlds (room_id, host_id, revision, state_json, updated_ms) SELECT ?, ?, 0, ?, ? WHERE EXISTS (SELECT 1 FROM multiplayer_rooms WHERE id = ?)`, id, playerId, JSON.stringify(initialWorld(data.world, playerId, nowMs)), nowMs, id));
    const result = await this.db.batch(statements);
    if (result[3].meta.changes !== 1) throw new HttpError(429, "active_room_limit");
    return { ...(await this.snapshot(room, nowMs)), selfId: playerId, sessionToken, invite };
  }
  async join(userId, room, data, nowMs) {
    // Compare in SQL as well; the same atomic INSERT enforces admission/capacity.
    const inviteHash = await hash(data.invite);
    if (room.invite_hash !== inviteHash) throw new HttpError(403, "invite_invalid");
    if (room.build_id !== data.buildId) throw new HttpError(409, "build_mismatch");
    await this.reserve(userId, "join", nowMs, POLICY.joinCooldownMs);
    const playerId = crypto.randomUUID();
    const sessionToken = token();
    const userKey = await hash(`${room.id}:${userId}`);
    const world = await this.world(room.id);
    if (world && room.owner_key === await hash(`sites-user:${userId}`)) {
      await this.stmt("DELETE FROM multiplayer_rooms WHERE id = ?", room.id).run();
      throw new HttpError(404, "room_unavailable");
    }
    let nextWorld, committed;
    if (world) {
      nextWorld = JSON.parse(world.state_json);
      const old = await this.stmt("SELECT id, last_seen_ms FROM multiplayer_players WHERE room_id = ?", room.id).all();
      const same = await this.stmt("SELECT id FROM multiplayer_players WHERE room_id = ? AND user_key = ?", room.id, userKey).first();
      for (const item of old.results) if (item.last_seen_ms <= nowMs - POLICY.presenceTtlMs || item.id === same?.id) releaseWorldPlayer(nextWorld, item.id);
      nextWorld._commit = crypto.randomUUID(); nextWorld.updatedAtMs = nowMs;
      committed = this.worldCommitExists(world, nextWorld);
    }
    const guard = world ? ` AND ${committed.sql}` : "";
    const values = world ? committed.values : [];
    const statements = [
      ...(world ? [this.stmt(`UPDATE multiplayer_worlds SET revision = revision + 1, state_json = ?, updated_ms = ? WHERE room_id = ? AND revision = ? AND EXISTS (SELECT 1 FROM multiplayer_rooms WHERE id = ? AND expires_ms > ?) AND EXISTS (SELECT 1 FROM multiplayer_players WHERE id = ? AND room_id = ? AND last_seen_ms > ?)`, JSON.stringify(nextWorld), nowMs, room.id, world.revision, room.id, nowMs, world.host_id, room.id, nowMs - POLICY.presenceTtlMs)] : []),
      this.stmt(`DELETE FROM multiplayer_players WHERE room_id = ? AND last_seen_ms <= ?${guard}`, room.id, nowMs - POLICY.presenceTtlMs, ...values),
      // Rejoining the same Site identity rotates its session and removes the old
      // actor atomically. One active actor per account, no email/name stored.
      this.stmt(`DELETE FROM multiplayer_players WHERE room_id = ? AND user_key = ?${guard}`, room.id, userKey, ...values),
      this.stmt(`INSERT INTO multiplayer_players
        (id, room_id, user_key, token_hash, avatar_json, x, y, z, last_action_ms, last_position_ms, last_seen_ms)
        SELECT ?, id, ?, ?, ?, spawn_x, spawn_y, spawn_z, ?, ?, ? FROM multiplayer_rooms
        WHERE id = ? AND invite_hash = ? AND build_id = ? AND expires_ms > ? AND
        (SELECT COUNT(*) FROM multiplayer_players WHERE room_id = ? AND last_seen_ms > ?) < ?${guard}`,
        playerId, userKey, await hash(sessionToken), JSON.stringify(data.avatar), nowMs, nowMs, nowMs,
        room.id, inviteHash, data.buildId, nowMs, room.id, nowMs - POLICY.presenceTtlMs, POLICY.capacity, ...values),
    ];
    const result = await this.db.batch(statements);
    if (world && result[0].meta.changes !== 1) throw new HttpError(409, "concurrent_update_retry");
    if (result.at(-1).meta.changes !== 1) throw new HttpError(409, "room_full_or_expired");
    return { ...(await this.snapshot(room, nowMs)), selfId: playerId, sessionToken };
  }
  async authenticate(userId, request, room, playerId, nowMs) {
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer [0-9a-f]{48}$/.test(authorization)) throw new HttpError(401, "session_required");
    const player = await this.stmt(
      "SELECT * FROM multiplayer_players WHERE id = ? AND room_id = ? AND user_key = ? AND token_hash = ? AND last_seen_ms > ?",
      playerId, room.id, await hash(`${room.id}:${userId}`), await hash(authorization.slice(7)), nowMs - POLICY.presenceTtlMs,
    ).first();
    if (!player) throw new HttpError(401, "session_expired_or_invalid");
    return player;
  }
  async action(room, player, operation, data, nowMs) {
    for (let attempt = 0; attempt < 4; attempt += 1) {
      const world = await this.world(room.id);
      if (!world) break;
      try { return await this.worldAction(room, world, player, operation, data, nowMs); }
      catch (error) {
        if (!(error instanceof HttpError) || error.code !== "concurrent_update_retry" || attempt === 3) throw error;
        const current = await this.stmt("SELECT * FROM multiplayer_players WHERE id = ? AND room_id = ? AND token_hash = ?", player.id, room.id, player.token_hash).first();
        if (!current) throw new HttpError(401, "session_expired_or_invalid");
        player = current;
      }
    }
    if (data.world !== undefined || data.actions !== undefined || data.drive !== undefined) throw new HttpError(409, "world_unavailable");
    if (operation === "leave") {
      await this.stmt("DELETE FROM multiplayer_players WHERE id = ? AND token_hash = ?", player.id, player.token_hash).run();
      return { left: true };
    }
    const waitMs = POLICY.intervalMs - (nowMs - player.last_action_ms);
    if (waitMs > 0) throw new HttpError(429, "update_rate_limited", { retryAfterMs: waitMs });
    let statement;
    if (operation === "snapshot") {
      statement = this.stmt(
        "UPDATE multiplayer_players SET last_action_ms = ?, last_seen_ms = ? WHERE id = ? AND last_action_ms = ? AND token_hash = ?",
        nowMs, nowMs, player.id, player.last_action_ms, player.token_hash,
      );
    } else {
      if (data.sequence <= player.sequence) throw new HttpError(409, "sequence_stale");
      const elapsed = Math.min(nowMs - player.last_position_ms, POLICY.maximumMovementCreditMs) / 1000;
      const horizontal = Math.hypot(data.position[0] - player.x, data.position[2] - player.z);
      const vertical = Math.abs(data.position[1] - player.y);
      if (horizontal > POLICY.maximumHorizontalMps * elapsed + 0.25 || vertical > POLICY.maximumVerticalMps * elapsed + 0.25) {
        throw new HttpError(422, "movement_out_of_range", { acceptedPlayer: publicPlayer(player) });
      }
      statement = this.stmt(`UPDATE multiplayer_players SET
        sequence = ?, x = ?, y = ?, z = ?, yaw = ?, motion = ?, avatar_json = ?,
        last_action_ms = ?, last_position_ms = ?, last_seen_ms = ?
        WHERE id = ? AND sequence = ? AND last_action_ms = ? AND token_hash = ?`,
        data.sequence, ...data.position, data.yaw, data.motion, JSON.stringify(data.avatar ?? JSON.parse(player.avatar_json)),
        nowMs, nowMs, nowMs, player.id, player.sequence, player.last_action_ms, player.token_hash);
    }
    const result = await statement.run();
    if (result.meta.changes !== 1) throw new HttpError(409, "concurrent_update_retry");
    return { ...(await this.snapshot(room, nowMs)), selfId: player.id };
  }
}

export function createRoomApi({ now = () => Date.now() } = {}) {
  return async (request, env) => {
    const url = new URL(request.url);
    if (!url.pathname.startsWith(PREFIX)) return null;
    try {
      const userId = identity(request);
      originGuard(request, url);
      if (!env.DB?.prepare || !env.DB?.batch) throw new HttpError(503, "room_storage_unavailable");
      const store = new D1Rooms(env.DB);
      const nowMs = now();
      if (url.pathname === `${PREFIX}rooms` && request.method === "POST") {
        const data = await bodyJson(request);
        exactKeys(data, ["buildId", "avatar", "position", "yaw", "world"]);
        return reply(await store.create(userId, {
          buildId: buildId(data.buildId), avatar: avatar(data.avatar), position: position(data.position), yaw: yaw(data.yaw), ...(data.world === undefined ? {} : { world: data.world }),
        }, nowMs), 201);
      }
      const matched = url.pathname.match(ROOM_ROUTE);
      if (!matched) throw new HttpError(404, "route_not_found");
      const [, roomId, branch, playerId, playerAction] = matched;
      const operation = ["join", "close"].includes(branch) ? branch : playerAction;
      const expectedMethod = operation === "snapshot" ? "GET" : "POST";
      if (request.method !== expectedMethod) return reply({ error: "method_not_allowed" }, 405, { allow: expectedMethod });
      const room = await store.room(roomId, nowMs);
      if (operation === "close") {
        exactKeys(await bodyJson(request), []);
        if (room.owner_key !== await hash(`sites-user:${userId}`)) throw new HttpError(403, "room_owner_required");
        await store.stmt("DELETE FROM multiplayer_rooms WHERE id = ?", room.id).run();
        return reply({ closed: true });
      }
      if (operation === "join") {
        const data = await bodyJson(request);
        exactKeys(data, ["invite", "buildId", "avatar"]);
        if (typeof data.invite !== "string" || !/^[0-9a-f]{32}$/.test(data.invite)) throw new HttpError(400, "invalid_invite_format");
        return reply(await store.join(userId, room, { invite: data.invite, buildId: buildId(data.buildId), avatar: avatar(data.avatar) }, nowMs), 201);
      }
      const player = await store.authenticate(userId, request, room, playerId, nowMs);
      let data = {};
      if (operation === "sync") {
        const raw = await bodyJson(request);
        exactKeys(raw, ["sequence", "position", "yaw", "motion", "avatar", "world", "actions", "drive"]);
        if (!Number.isSafeInteger(raw.sequence) || raw.sequence < 1 || raw.sequence > 2147483647) throw new HttpError(400, "invalid_sequence");
        if (!MOTIONS.has(raw.motion)) throw new HttpError(400, "invalid_motion");
        data = { sequence: raw.sequence, position: position(raw.position), yaw: yaw(raw.yaw), motion: raw.motion };
        if (raw.avatar !== undefined) data.avatar = avatar(raw.avatar);
        for (const key of ["world", "actions", "drive"]) if (raw[key] !== undefined) data[key] = raw[key];
      } else if (operation === "leave") {
        exactKeys(await bodyJson(request), []);
      }
      return reply(await store.action(room, player, operation, data, nowMs));
    } catch (error) {
      if (!(error instanceof HttpError)) {
        // Never serialize database messages, identity headers, or bearer tokens.
        return reply({ error: "room_service_unavailable" }, 503);
      }
      return reply({ error: error.code, ...error.details }, error.status,
        error.status === 429 ? { "retry-after": String(Math.max(1, Math.ceil((error.details.retryAfterMs ?? 1000) / 1000))) } : {});
    }
  };
}
