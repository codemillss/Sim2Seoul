-- Local SQLite fixture schema mirrored by generated Sites/Drizzle migrations.
-- Hosted databases use normal migration history; this is not runtime schema DDL.
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

CREATE TABLE multiplayer_worlds (
  room_id TEXT PRIMARY KEY NOT NULL REFERENCES multiplayer_rooms(id) ON DELETE CASCADE,
  host_id TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 0,
  state_json TEXT NOT NULL,
  updated_ms INTEGER NOT NULL
);
CREATE TABLE multiplayer_world_actions (
  room_id TEXT NOT NULL REFERENCES multiplayer_worlds(room_id) ON DELETE CASCADE,
  player_id TEXT NOT NULL,
  request_id TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  result_json TEXT NOT NULL,
  created_ms INTEGER NOT NULL,
  PRIMARY KEY (room_id, player_id, request_id)
);
