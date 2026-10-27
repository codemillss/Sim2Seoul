import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

const overlay = new URL("../site-worker/overlay/", import.meta.url);
const oldMigration = readFileSync(new URL("drizzle/0000_mighty_may_parker.sql", overlay), "utf8");
const migration = readFileSync(new URL("drizzle/0001_shared_world.sql", overlay), "utf8");
const sha = value => createHash("sha256").update(value).digest("hex");

function fixture(t) {
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  db.exec("PRAGMA foreign_keys = ON");
  db.exec(oldMigration);
  db.exec(`INSERT INTO multiplayer_rooms VALUES ('room', 'owner', 'invite', 'build', 1, 2, 3, 100, 200);
    INSERT INTO multiplayer_rooms VALUES ('other', 'owner2', 'invite2', 'build', 4, 5, 6, 100, 200);
    INSERT INTO multiplayer_players VALUES ('player', 'room', 'account', 'token', '{}', 9, 1, 2, 3, .5, 'walk', 110, 120, 130);
    INSERT INTO multiplayer_rate_limits VALUES ('rate', 42);`);
  return db;
}

function world(db, room = "room") {
  db.prepare("INSERT INTO multiplayer_worlds (room_id, host_id, state_json, updated_ms) VALUES (?, 'player', ?, 150)")
    .run(room, JSON.stringify({ entities: [], recentActions: [] }));
}

function receipt(db, room = "room", player = "player", request = "request") {
  db.prepare("INSERT INTO multiplayer_world_actions VALUES (?, ?, ?, 'hash', '{\"ok\":true}', 151)")
    .run(room, player, request);
}

test("additive migration preserves the deployed 0000 bytes and journal chain", () => {
  assert.equal(sha(oldMigration), "23a8823a59fd02f9ec80b57f96f0d188a02ed64903b7effddbe491d639ad4257");
  const oldSnapshot = readFileSync(new URL("drizzle/meta/0000_snapshot.json", overlay));
  assert.equal(sha(oldSnapshot), "1f0d12ce1e5694a308a4713c75ff16f539ea37475240be417e55657140bb08da");
  const journal = JSON.parse(readFileSync(new URL("drizzle/meta/_journal.json", overlay)));
  assert.deepEqual(journal.entries.map(entry => [entry.idx, entry.tag]), [[0, "0000_mighty_may_parker"], [1, "0001_shared_world"]]);
  const first = JSON.parse(oldSnapshot);
  const second = JSON.parse(readFileSync(new URL("drizzle/meta/0001_snapshot.json", overlay)));
  assert.equal(second.prevId, first.id);
  assert.equal(Object.keys(second.tables).length, 5);
});

test("upgrade of an occupied old database preserves every room, player and rate-limit value", t => {
  const db = fixture(t);
  const before = ["multiplayer_rooms", "multiplayer_players", "multiplayer_rate_limits"]
    .map(table => db.prepare(`SELECT * FROM ${table} ORDER BY 1`).all());
  db.exec(migration);
  const after = ["multiplayer_rooms", "multiplayer_players", "multiplayer_rate_limits"]
    .map(table => db.prepare(`SELECT * FROM ${table} ORDER BY 1`).all());
  assert.deepEqual(after, before);
  assert.deepEqual(db.prepare("PRAGMA foreign_key_check").all(), []);
  world(db);
  assert.deepEqual({ ...db.prepare("SELECT * FROM multiplayer_worlds").get() }, {
    room_id: "room", host_id: "player", revision: 0,
    state_json: '{"entities":[],"recentActions":[]}', updated_ms: 150,
  });
});

test("receipt identity is scoped to room and player and survives player departure", t => {
  const db = fixture(t);
  db.exec(migration);
  world(db); world(db, "other");
  receipt(db);
  assert.throws(() => receipt(db), /UNIQUE constraint failed/);
  receipt(db, "room", "another-player");
  receipt(db, "other");
  db.prepare("DELETE FROM multiplayer_players WHERE id = 'player'").run();
  assert.equal(db.prepare("SELECT count(*) AS n FROM multiplayer_world_actions").get().n, 3);
  assert.equal(db.prepare("PRAGMA foreign_key_list(multiplayer_world_actions)").all().length, 1);
  assert.deepEqual(db.prepare("PRAGMA foreign_key_check").all(), []);
});

test("room deletion cascades through the world to receipts without deleting another room", t => {
  const db = fixture(t);
  db.exec(migration);
  world(db); world(db, "other"); receipt(db); receipt(db, "other");
  db.prepare("DELETE FROM multiplayer_rooms WHERE id = 'room'").run();
  assert.equal(db.prepare("SELECT count(*) AS n FROM multiplayer_players").get().n, 0);
  assert.deepEqual(db.prepare("SELECT room_id FROM multiplayer_worlds").all().map(row => row.room_id), ["other"]);
  assert.deepEqual(db.prepare("SELECT room_id FROM multiplayer_world_actions").all().map(row => row.room_id), ["other"]);
  db.prepare("DELETE FROM multiplayer_worlds WHERE room_id = 'other'").run();
  assert.equal(db.prepare("SELECT count(*) AS n FROM multiplayer_world_actions").get().n, 0);
  assert.equal(db.prepare("SELECT count(*) AS n FROM multiplayer_rooms").get().n, 1);
  assert.deepEqual(db.prepare("PRAGMA foreign_key_check").all(), []);
});

test("new rows reject absent parents, missing required data and duplicate world ownership", t => {
  const db = fixture(t);
  db.exec(migration);
  assert.throws(() => world(db, "absent"), /FOREIGN KEY constraint failed/);
  assert.throws(() => receipt(db), /FOREIGN KEY constraint failed/);
  world(db);
  assert.throws(() => world(db), /UNIQUE constraint failed/);
  assert.throws(() => db.prepare("INSERT INTO multiplayer_world_actions VALUES ('room', 'player', 'request', NULL, '{}', 1)").run(), /NOT NULL constraint failed/);
  assert.throws(() => db.prepare("UPDATE multiplayer_worlds SET host_id = NULL").run(), /NOT NULL constraint failed/);
});

test("overlay manifest hashes include the generated migration and both snapshot generations", () => {
  const manifest = JSON.parse(readFileSync(new URL("../site-worker/overlay.json", import.meta.url)));
  for (const path of ["db/schema.ts", "drizzle/0000_mighty_may_parker.sql", "drizzle/0001_shared_world.sql", "drizzle/meta/0000_snapshot.json", "drizzle/meta/0001_snapshot.json", "drizzle/meta/_journal.json"]) {
    const entry = manifest.files.find(file => file.path === path);
    assert.ok(entry, path);
    assert.equal(sha(readFileSync(new URL(path, overlay))), entry.sha256, path);
  }
});

test("generated hosted world tables match the actual local API SQL columns and foreign keys", t => {
  const hosted = fixture(t);
  hosted.exec(migration);
  const local = new DatabaseSync(":memory:");
  t.after(() => local.close());
  local.exec("PRAGMA foreign_keys = ON");
  local.exec(readFileSync(new URL("./schema.sql", import.meta.url), "utf8"));
  for (const table of ["multiplayer_worlds", "multiplayer_world_actions"]) {
    assert.deepEqual(hosted.prepare(`PRAGMA table_info(${table})`).all(), local.prepare(`PRAGMA table_info(${table})`).all(), table);
    assert.deepEqual(hosted.prepare(`PRAGMA foreign_key_list(${table})`).all(), local.prepare(`PRAGMA foreign_key_list(${table})`).all(), table);
  }
});
