/**
 * Bounded Sites/D1 HTTP presence prototype. Not connected to the deployed game.
 * Call createRoomApi()(request, env) behind Sites authenticated dispatch only.
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
  maximumBodyBytes: 2048,
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
    return {
      protocol: POLICY.protocol,
      serverNowMs: nowMs,
      room: { id: room.id, buildId: room.build_id, expiresAtMs: room.expires_ms, capacity: POLICY.capacity },
      transport: { type: "http-poll", intervalMs: POLICY.intervalMs, idleHeartbeatMs: POLICY.idleHeartbeatMs, interpolationMs: POLICY.interpolationMs },
      players: result.results.map(publicPlayer),
    };
  }
  async room(id, nowMs) {
    const room = await this.stmt("SELECT * FROM multiplayer_rooms WHERE id = ? AND expires_ms > ?", id, nowMs).first();
    if (!room) throw new HttpError(404, "room_unavailable");
    return room;
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
    const result = await this.db.batch([
      // Bounded opportunistic garbage collection; no request-time schema DDL.
      this.stmt("DELETE FROM multiplayer_rooms WHERE id IN (SELECT id FROM multiplayer_rooms WHERE expires_ms <= ? LIMIT 32)", nowMs),
      this.stmt("DELETE FROM multiplayer_rate_limits WHERE key IN (SELECT key FROM multiplayer_rate_limits WHERE last_ms < ? LIMIT 32)", nowMs - POLICY.roomLifetimeMs),
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
    ]);
    if (result[2].meta.changes !== 1) throw new HttpError(429, "active_room_limit");
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
    const result = await this.db.batch([
      this.stmt("DELETE FROM multiplayer_players WHERE room_id = ? AND last_seen_ms <= ?", room.id, nowMs - POLICY.presenceTtlMs),
      // Rejoining the same Site identity rotates its session and removes the old
      // actor atomically. One active actor per account, no email/name stored.
      this.stmt("DELETE FROM multiplayer_players WHERE room_id = ? AND user_key = ?", room.id, userKey),
      this.stmt(`INSERT INTO multiplayer_players
        (id, room_id, user_key, token_hash, avatar_json, x, y, z, last_action_ms, last_position_ms, last_seen_ms)
        SELECT ?, id, ?, ?, ?, spawn_x, spawn_y, spawn_z, ?, ?, ? FROM multiplayer_rooms
        WHERE id = ? AND invite_hash = ? AND build_id = ? AND expires_ms > ? AND
        (SELECT COUNT(*) FROM multiplayer_players WHERE room_id = ? AND last_seen_ms > ?) < ?`,
        playerId, userKey, await hash(sessionToken), JSON.stringify(data.avatar), nowMs, nowMs, nowMs,
        room.id, inviteHash, data.buildId, nowMs, room.id, nowMs - POLICY.presenceTtlMs, POLICY.capacity),
    ]);
    if (result[2].meta.changes !== 1) throw new HttpError(409, "room_full_or_expired");
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
        exactKeys(data, ["buildId", "avatar", "position", "yaw"]);
        return reply(await store.create(userId, {
          buildId: buildId(data.buildId), avatar: avatar(data.avatar), position: position(data.position), yaw: yaw(data.yaw),
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
        exactKeys(raw, ["sequence", "position", "yaw", "motion", "avatar"]);
        if (!Number.isSafeInteger(raw.sequence) || raw.sequence < 1 || raw.sequence > 2147483647) throw new HttpError(400, "invalid_sequence");
        if (!MOTIONS.has(raw.motion)) throw new HttpError(400, "invalid_motion");
        data = { sequence: raw.sequence, position: position(raw.position), yaw: yaw(raw.yaw), motion: raw.motion };
        if (raw.avatar !== undefined) data.avatar = avatar(raw.avatar);
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
