import { index, integer, real, sqliteTable, text, unique } from "drizzle-orm/sqlite-core";

export const multiplayerRooms = sqliteTable("multiplayer_rooms", {
  id: text("id").primaryKey().notNull(),
  ownerKey: text("owner_key").notNull(),
  inviteHash: text("invite_hash").notNull(),
  buildId: text("build_id").notNull(),
  spawnX: real("spawn_x").notNull(), spawnY: real("spawn_y").notNull(), spawnZ: real("spawn_z").notNull(),
  createdMs: integer("created_ms").notNull(), expiresMs: integer("expires_ms").notNull(),
}, table => [
  index("multiplayer_rooms_owner_expiry").on(table.ownerKey, table.expiresMs),
  index("multiplayer_rooms_expiry").on(table.expiresMs),
]);

export const multiplayerPlayers = sqliteTable("multiplayer_players", {
  id: text("id").primaryKey().notNull(),
  roomId: text("room_id").notNull().references(() => multiplayerRooms.id, { onDelete: "cascade" }),
  userKey: text("user_key").notNull(), tokenHash: text("token_hash").notNull(), avatarJson: text("avatar_json").notNull(),
  sequence: integer("sequence").notNull().default(0),
  x: real("x").notNull(), y: real("y").notNull(), z: real("z").notNull(),
  yaw: real("yaw").notNull().default(0), motion: text("motion").notNull().default("idle"),
  lastActionMs: integer("last_action_ms").notNull(), lastPositionMs: integer("last_position_ms").notNull(), lastSeenMs: integer("last_seen_ms").notNull(),
}, table => [
  unique().on(table.roomId, table.userKey),
  index("multiplayer_players_room_presence").on(table.roomId, table.lastSeenMs),
]);

export const multiplayerRateLimits = sqliteTable("multiplayer_rate_limits", {
  key: text("key").primaryKey().notNull(), lastMs: integer("last_ms").notNull(),
});
