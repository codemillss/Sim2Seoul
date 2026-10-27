/** Two full headless production games. Test coordination is loopback/memory only. */
import { createServer } from "node:http";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { createWriteStream } from "node:fs";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { pipeline } from "node:stream/promises";
import { createHash } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { startDevServer } from "./dev-server.mjs";

const ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const ENGINE = "/Applications/Godot.app/Contents/MacOS/Godot";
const SOURCES = [
  "tests/game/check_shared_city_world.gd", "game/scripts/explore_walk.gd",
  "game/scripts/multiplayer/shared_city_walk.gd", "game/scripts/multiplayer/remote_resident.gd",
  "game/scripts/multiplayer/room_presence_client.gd", "tools/web/multiplayer/check-game-pair.mjs",
  "tools/web/multiplayer/dev-server.mjs", "tools/web/multiplayer/room-api.mjs",
  "tools/web/multiplayer/local-d1.mjs", "tools/web/multiplayer/schema.sql",
];
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const delay = milliseconds => new Promise(accept => { const timer = setTimeout(accept, milliseconds); timer.unref(); });
const invitePattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[0-9a-f]{32}$/;
function reply(outgoing, status, body) {
  outgoing.writeHead(status, { "content-type": "application/json", "cache-control": "no-store", "x-content-type-options": "nosniff" });
  outgoing.end(JSON.stringify(body));
}
async function smallObject(incoming) {
  if (incoming.headers["content-type"]?.split(";", 1)[0] !== "application/json") throw new Error("json_required");
  let bytes = 0; const parts = [];
  for await (const part of incoming) {
    bytes += part.length;
    if (bytes > 512) throw new Error("body_too_large");
    parts.push(part);
  }
  const body = JSON.parse(Buffer.concat(parts).toString("utf8"));
  if (!body || Array.isArray(body) || typeof body !== "object") throw new Error("object_required");
  return body;
}

export async function createCoordinator() {
  // A fresh fake-local-room test only. Never accepts account/bearer/cookie state.
  let invite = ""; let origin;
  const state = { a: { stage: "", stages: [] }, b: { stage: "", stages: [] } };
  const server = createServer(async (incoming, outgoing) => {
    try {
      if (incoming.socket.remoteAddress !== "127.0.0.1" || incoming.headers.host !== new URL(origin).host) return reply(outgoing, 403, { error: "loopback_only" });
      if (incoming.headers.origin && incoming.headers.origin !== origin) return reply(outgoing, 403, { error: "same_origin_only" });
      if (incoming.method === "GET" && incoming.url === "/invite") return reply(outgoing, 200, { code: invite });
      if (incoming.method === "GET" && incoming.url === "/state") return reply(outgoing, 200, state);
      if (incoming.method !== "POST" || !["/invite", "/state"].includes(incoming.url)) return reply(outgoing, 404, { error: "route_not_found" });
      const body = await smallObject(incoming);
      if (incoming.url === "/invite") {
        if (Object.keys(body).length !== 1 || !invitePattern.test(body.code)) return reply(outgoing, 400, { error: "invalid_invite" });
        if (invite && invite !== body.code) return reply(outgoing, 409, { error: "invite_already_set" });
        invite = body.code;
        return reply(outgoing, 200, { stored: true });
      }
      if (Object.keys(body).sort().join(",") !== "role,stage" || !["a", "b"].includes(body.role) || typeof body.stage !== "string" || !/^[a-z][a-z0-9_]{0,63}$/.test(body.stage) || /^[a-f0-9]{32,64}$/.test(body.stage)) return reply(outgoing, 400, { error: "invalid_stage" });
      const row = state[body.role]; row.stage = body.stage;
      if (!row.stages.includes(body.stage)) row.stages.push(body.stage);
      row.stages = row.stages.slice(-32);
      return reply(outgoing, 200, { stored: true });
    } catch { reply(outgoing, 400, { error: "invalid_coordination_request" }); }
  });
  server.requestTimeout = 10_000; server.headersTimeout = 10_000;
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  origin = `http://127.0.0.1:${server.address().port}`;
  return { origin, server, publicState() {
    return { invite_published: Boolean(invite), a: { ...state.a, stages: [...state.a.stages] }, b: { ...state.b, stages: [...state.b.stages] } };
  }, async close() {
    invite = "";
    server.closeAllConnections();
    await new Promise((accept, reject) => server.close(error => error ? reject(error) : accept()));
  } };
}

async function sourceHashes() {
  return Object.fromEntries(await Promise.all(SOURCES.map(async path => [path, digest(await readFile(resolve(ROOT, path)))])));
}
function startGame(role, engine, apiOrigin, coordinatorOrigin, reportDir, ownerGraphics) {
  const files = Object.fromEntries(["report", "engine", "stdout", "stderr"].map(kind => [kind, resolve(reportDir, `${role}_${kind}.${kind === "report" ? "json" : "log"}`)]));
  const args = [...(ownerGraphics && role === "a" ? [] : ["--headless"]), "--path", resolve(ROOT, "game"), "--log-file", files.engine,
    "--script", resolve(ROOT, "tests/game/check_shared_city_world.gd"), "--", `--room-server=${apiOrigin}`,
    `--test-role=${role}`, `--test-coord=${coordinatorOrigin}`, `--test-report=${files.report}`];
  if (ownerGraphics && role === "a") args.push("--test-owner-graphics");
  const child = spawn(engine, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
  const record = { role, child, files, command: [engine, ...args], pid: child.pid ?? null, exited: false, exit_code: null, signal: null, spawn_error: null };
  const exited = new Promise(accept => {
    child.once("error", error => { record.spawn_error = error.code ?? "spawn_failed"; });
    child.once("close", (code, signal) => { record.exited = true; record.exit_code = code; record.signal = signal; accept(); });
  });
  record.done = Promise.all([exited, pipeline(child.stdout, createWriteStream(files.stdout)), pipeline(child.stderr, createWriteStream(files.stderr))]).then(() => record);
  return record;
}
async function stopGames(records) {
  for (const record of records) if (!record.exited && record.pid) record.child.kill("SIGTERM");
  await Promise.race([Promise.allSettled(records.map(record => record.done)), delay(1500)]);
  for (const record of records) if (!record.exited && record.pid) record.child.kill("SIGKILL");
  await Promise.race([Promise.allSettled(records.map(record => record.done)), delay(3000)]);
}
async function artifact(path) {
  try { const bytes = await readFile(path); return { bytes: bytes.length, sha256: digest(bytes) }; }
  catch { return null; }
}
async function summarize(record) {
  const files = {};
  let errors = 0; let engineErrors = 0;
  for (const kind of ["stdout", "stderr", "engine", "report"]) {
    files[kind] = { path: record.files[kind], ...(await artifact(record.files[kind]) ?? { missing: true }) };
    if (["stdout", "stderr", "engine"].includes(kind) && !files[kind].missing) {
      const text = await readFile(record.files[kind], "utf8");
      const count = (text.match(/(?:SCRIPT )?ERROR:/g) ?? []).length;
      if (kind === "engine") engineErrors = count;
      else errors += count;
    }
  }
  let reportResult = null;
  try { reportResult = JSON.parse(await readFile(record.files.report, "utf8")).result; } catch { /* Missing report is a failure below. */ }
  return { role: record.role, pid: record.pid, command: record.command, exit_code: record.exit_code, signal: record.signal,
    spawn_error: record.spawn_error, error_count: errors, engine_error_count: engineErrors, report_result: reportResult,
    passed: record.exited && record.exit_code === 0 && !record.signal && !record.spawn_error && errors === 0 && engineErrors === 0 && reportResult === "PASS", files };
}

export async function runGamePair({ reportDir = resolve(ROOT, "data/reports/shared_city/20261026/world_pair_attempt01"), engine = ENGINE, ownerGraphics = false } = {}) {
  reportDir = resolve(reportDir); engine = resolve(engine);
  await access(engine, constants.X_OK);
  await mkdir(dirname(reportDir), { recursive: true });
  await mkdir(reportDir); // Deliberately reject an existing evidence directory.
  const started = Date.now(); const records = [];
  let api, coordinator, timer, signalHandler;
  const record = { task: "EXP40_TWO_FULL_GAME_PROCESSES", started_at_utc: new Date(started).toISOString(),
    result: "FAIL", timeout_ms: 90_000, timed_out: false, failure: null, source_sha256_before: null, source_sha256_after: null,
    render_modes: { a: ownerGraphics ? "native_graphical" : "headless", b: "headless" },
    scope: ownerGraphics ? "Two independent full production explore_walk games: native GPU owner and headless guest, real city/AI/player physics. Owner PNGs use an explicitly labelled fixture camera/markers and restore the product camera. No CUA, public hosting/authentication, shared world physics or performance acceptance. Root-owned8766 is untouched." : "Two independent full production explore_walk Godot processes with real city, AI and player physics, both headless. No GUI/pixels, hosted-production authentication, public access, remote shared physics or performance acceptance. Root-owned server8766 is not used or stopped." };
  try {
    record.source_sha256_before = await sourceHashes();
    api = await startDevServer({ apiOnly: true, port: 0 });
    coordinator = await createCoordinator();
    record.api_origin = api.origin; record.coordinator_origin = coordinator.origin;
    for (const role of ["a", "b"]) records.push(startGame(role, engine, api.origin, coordinator.origin, reportDir, ownerGraphics));
    const allFinished = Promise.all(records.map(async child => {
      await child.done;
      const summary = await summarize(child);
      if (!summary.passed) throw new Error(`role_${child.role}_failed`);
    }));
    const watchdog = new Promise((_, reject) => { timer = setTimeout(() => { record.timed_out = true; reject(new Error("pair_timeout")); }, record.timeout_ms); });
    const interrupted = new Promise((_, reject) => {
      signalHandler = () => reject(new Error("interrupted"));
      process.once("SIGINT", signalHandler); process.once("SIGTERM", signalHandler);
    });
    await Promise.race([allFinished, watchdog, interrupted]);
    record.result = "PASS";
  } catch (error) { record.failure = String(error.message ?? "pair_failed"); }
  finally {
    clearTimeout(timer);
    if (signalHandler) { process.removeListener("SIGINT", signalHandler); process.removeListener("SIGTERM", signalHandler); }
    record.cleanup_errors = [];
    try { await stopGames(records); } catch { record.cleanup_errors.push("child_cleanup_failed"); }
    if (coordinator) {
      record.coordination = coordinator.publicState();
      try { await coordinator.close(); } catch { record.cleanup_errors.push("coordinator_cleanup_failed"); }
    }
    if (api) {
      try { api.server.closeAllConnections(); await api.close(); } catch { record.cleanup_errors.push("api_cleanup_failed"); }
    }
    try { record.source_sha256_after = await sourceHashes(); } catch { record.failure ??= "source_snapshot_unavailable"; }
    record.source_unchanged = JSON.stringify(record.source_sha256_before) === JSON.stringify(record.source_sha256_after);
    record.games = await Promise.all(records.map(summarize));
    if (record.cleanup_errors.length || !record.source_unchanged || record.games.length !== 2 || record.games.some(game => !game.passed)) record.result = "FAIL";
    record.elapsed_ms = Date.now() - started;
    const path = resolve(reportDir, "summary.json");
    await writeFile(path, JSON.stringify(record, null, 2) + "\n");
    return { record, path };
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { "report-dir": { type: "string" }, engine: { type: "string" }, "owner-graphics": { type: "boolean", default: false } } });
  const result = await runGamePair({ ...(values["report-dir"] ? { reportDir: values["report-dir"] } : {}), ...(values.engine ? { engine: values.engine } : {}), ownerGraphics: values["owner-graphics"] });
  console.log(JSON.stringify({ result: result.record.result, report: result.path, elapsed_ms: result.record.elapsed_ms,
    games: result.record.games.map(game => ({ role: game.role, pid: game.pid, exit_code: game.exit_code, error_count: game.error_count, engine_error_count: game.engine_error_count, report_result: game.report_result })) }));
  process.exitCode = result.record.result === "PASS" ? 0 : 1;
}
