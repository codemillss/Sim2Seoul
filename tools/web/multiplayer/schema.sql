-- Local prototype schema. Not a deployed or applied Sites migration.
-- A hosted integration must generate and commit a normal Sites/Drizzle migration.
CREATE TABLE multiplayer_rooms (
  id TEXT PRIMARY KEY NOT NULL,
  owner_key TEXT NOT NULL,
  invite_hash TEXT NOT NULL,
  build_id TEXT NOT NULL,
  spawn_x REAL NOT NULL,
  spawn_y REAL NOT NULL,
  spawn_z REAL NOT NULL,
  created_ms INTEGER NOT NULL,
  expires_ms INTEGER NOT NULL
);
CREATE INDEX multiplayer_rooms_owner_expiry ON multiplayer_rooms(owner_key, expires_ms);
CREATE INDEX multiplayer_rooms_expiry ON multiplayer_rooms(expires_ms);

CREATE TABLE multiplayer_players (
  id TEXT PRIMARY KEY NOT NULL,
  room_id TEXT NOT NULL REFERENCES multiplayer_rooms(id) ON DELETE CASCADE,
  user_key TEXT NOT NULL,
  token_hash TEXT NOT NULL,
  avatar_json TEXT NOT NULL,
  sequence INTEGER NOT NULL DEFAULT 0,
  x REAL NOT NULL,
  y REAL NOT NULL,
  z REAL NOT NULL,
  yaw REAL NOT NULL DEFAULT 0,
  motion TEXT NOT NULL DEFAULT 'idle',
  last_action_ms INTEGER NOT NULL,
  last_position_ms INTEGER NOT NULL,
  last_seen_ms INTEGER NOT NULL,
  UNIQUE(room_id, user_key)
);
CREATE INDEX multiplayer_players_room_presence ON multiplayer_players(room_id, last_seen_ms);

CREATE TABLE multiplayer_rate_limits (
  key TEXT PRIMARY KEY NOT NULL,
  last_ms INTEGER NOT NULL
);
