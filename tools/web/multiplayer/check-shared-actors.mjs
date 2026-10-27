/** EXP41_SHARED_ACTORS: bounded two-game acceptance, loopback coordination only. */
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
  "game/project.godot", "tests/game/check_shared_city_actors.gd",
  "game/scripts/explore_walk.gd", "game/scripts/multiplayer/room_presence_client.gd",
  "game/scripts/multiplayer/shared_city_walk.gd", "game/scripts/multiplayer/remote_resident.gd",
  "game/scripts/multiplayer/shared_city_vehicles.gd", "game/scripts/multiplayer/shared_city_npcs.gd",
  "game/scripts/traffic/vehicle.gd", "game/scripts/traffic/traffic_manager.gd",
  "game/scripts/street_pedestrians.gd", "game/scripts/exploration_pedestrian_avoidance.gd",
  "game/scripts/neighborhood_population.gd", "game/scripts/drivable_car_service.gd",
  "tools/web/multiplayer/check-shared-actors.mjs", "tools/web/multiplayer/dev-server.mjs",
  "tools/web/multiplayer/room-api.mjs", "tools/web/multiplayer/local-d1.mjs", "tools/web/multiplayer/schema.sql",
];
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const delay = milliseconds => new Promise(accept => { const timer = setTimeout(accept, milliseconds); timer.unref(); });
const invitePattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[0-9a-f]{32}$/;
const entityPattern = /^[A-Za-z0-9:_-]{1,128}$/;
const SECRET_PATTERNS = [
  /Bearer\s+[A-Za-z0-9._~+\/-]+/i,
  /sim2seoul_dev_\d+=[a-f0-9]{64}/i,
  /["']sessionToken["']\s*:\s*["'][a-f0-9]{48}["']/i,
  /\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.[0-9a-f]{32}\b/i,
  /(?<![a-f0-9])[a-f0-9]{48}(?![a-f0-9])/i,
];
function reply(outgoing, status, body) {
  outgoing.writeHead(status, { "content-type": "application/json", "cache-control": "no-store", "x-content-type-options": "nosniff" });
  outgoing.end(JSON.stringify(body));
}
async function smallObject(incoming) {
  if (incoming.headers["content-type"]?.split(";", 1)[0] !== "application/json") throw new Error("json_required");
  let bytes = 0; const parts = [];
  for await (const part of incoming) {
    bytes += part.length;
    if (bytes > 4096) throw new Error("body_too_large");
    parts.push(part);
  }
  const body = JSON.parse(Buffer.concat(parts).toString("utf8"));
  if (!body || Array.isArray(body) || typeof body !== "object") throw new Error("object_required");
  return body;
}

function validContext(body) {
  return Object.keys(body).sort().join(",") === "carId,dogId,npcId,spawn"
    && [body.carId, body.npcId, body.dogId].every(id => typeof id === "string" && entityPattern.test(id))
    && new Set([body.carId, body.npcId, body.dogId]).size === 3
    && Array.isArray(body.spawn) && body.spawn.length === 3 && body.spawn.every(Number.isFinite)
    && Math.abs(body.spawn[0]) <= 1000 && body.spawn[1] >= -100 && body.spawn[1] <= 500 && Math.abs(body.spawn[2]) <= 1000;
}

export async function createCoordinator() {
  // A fresh fake-local-room test only. Never accepts account/bearer/cookie state.
  let invite = ""; let context = null; let origin;
  const state = { a: { stage: "", stages: [] }, b: { stage: "", stages: [] } };
  const server = createServer(async (incoming, outgoing) => {
    try {
      const hosts = incoming.rawHeaders.filter((_, index) => index % 2 === 0).filter(name => name.toLowerCase() === "host");
      if (hosts.length !== 1 || incoming.socket.remoteAddress !== "127.0.0.1" || incoming.headers.host !== new URL(origin).host) return reply(outgoing, 403, { error: "loopback_only" });
      if (incoming.headers.cookie !== undefined || incoming.headers.authorization !== undefined || Object.keys(incoming.headers).some(name => name.startsWith("oai-authenticated-"))) return reply(outgoing, 403, { error: "credentials_not_accepted" });
      if (incoming.headers.origin && incoming.headers.origin !== origin) return reply(outgoing, 403, { error: "same_origin_only" });
      if (incoming.method === "GET" && incoming.url === "/invite") return reply(outgoing, 200, { code: invite });
      if (incoming.method === "GET" && incoming.url === "/state") return reply(outgoing, 200, state);
      if (incoming.method === "GET" && incoming.url === "/context") return reply(outgoing, 200, context ?? {});
      if (incoming.method !== "POST" || !["/invite", "/state", "/context"].includes(incoming.url)) return reply(outgoing, 404, { error: "route_not_found" });
      if (incoming.headers.origin !== origin) return reply(outgoing, 403, { error: "same_origin_only" });
      const body = await smallObject(incoming);
      if (incoming.url === "/invite") {
        if (Object.keys(body).length !== 1 || !invitePattern.test(body.code)) return reply(outgoing, 400, { error: "invalid_invite" });
        if (invite && invite !== body.code) return reply(outgoing, 409, { error: "invite_already_set" });
        invite = body.code;
        return reply(outgoing, 200, { stored: true });
      }
      if (incoming.url === "/context") {
        if (!validContext(body)) return reply(outgoing, 400, { error: "invalid_context" });
        const accepted = { carId: body.carId, npcId: body.npcId, dogId: body.dogId, spawn: [...body.spawn] };
        if (context && JSON.stringify(context) !== JSON.stringify(accepted)) return reply(outgoing, 409, { error: "context_already_set" });
        context = accepted;
        return reply(outgoing, 200, { stored: true });
      }
      if (Object.keys(body).sort().join(",") !== "role,stage" || !["a", "b"].includes(body.role) || typeof body.stage !== "string" || !/^[a-z][a-z0-9_]{0,63}$/.test(body.stage) || /^[a-f0-9]{32,64}$/.test(body.stage)) return reply(outgoing, 400, { error: "invalid_stage" });
      const row = state[body.role]; row.stage = body.stage;
      if (!row.stages.includes(body.stage)) row.stages.push(body.stage);
      row.stages = row.stages.slice(-64);
      return reply(outgoing, 200, { stored: true });
    } catch { reply(outgoing, 400, { error: "invalid_coordination_request" }); }
  });
  server.requestTimeout = 10_000; server.headersTimeout = 10_000;
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  origin = `http://127.0.0.1:${server.address().port}`;
  return { origin, server, publicState() {
    return { invite_published: Boolean(invite), fixture_context: context ? { ...context, spawn: [...context.spawn] } : null,
      a: { ...state.a, stages: [...state.a.stages] }, b: { ...state.b, stages: [...state.b.stages] } };
  }, async close() {
    invite = ""; context = null;
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
    "--script", resolve(ROOT, "tests/game/check_shared_city_actors.gd"), "--", `--room-server=${apiOrigin}`,
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
  let errors = 0; let engineErrors = 0; let secretFree = true;
  for (const kind of ["stdout", "stderr", "engine", "report"]) {
    files[kind] = { path: record.files[kind], ...(await artifact(record.files[kind]) ?? { missing: true }) };
    if (["stdout", "stderr", "engine"].includes(kind) && !files[kind].missing) {
      const text = await readFile(record.files[kind], "utf8");
      if (SECRET_PATTERNS.some(pattern => pattern.test(text))) secretFree = false;
      const count = (text.match(/(?:SCRIPT )?ERROR:/g) ?? []).length;
      if (kind === "engine") engineErrors = count;
      else errors += count;
    }
  }
  let reportResult = null; let settingsUnchanged = false; let fixtureChecks = null;
  try {
    const text = await readFile(record.files.report, "utf8");
    if (SECRET_PATTERNS.some(pattern => pattern.test(text))) secretFree = false;
    const report = JSON.parse(text);
    reportResult = report.result;
    settingsUnchanged = report.user_settings_before !== undefined && report.user_settings_after !== undefined
      && JSON.stringify(report.user_settings_before) === JSON.stringify(report.user_settings_after);
    fixtureChecks = { total: report.checks, failed: report.failed };
  } catch { /* Missing or malformed report is a failure below. */ }
  return { role: record.role, pid: record.pid, command: record.command, exit_code: record.exit_code, signal: record.signal,
    spawn_error: record.spawn_error, error_count: errors, engine_error_count: engineErrors, report_result: reportResult,
    raw_artifacts_secret_free: secretFree, settings_unchanged: settingsUnchanged, fixture_checks: fixtureChecks,
    passed: record.exited && record.exit_code === 0 && !record.signal && !record.spawn_error && errors === 0 && engineErrors === 0
      && reportResult === "PASS" && settingsUnchanged && secretFree && Object.values(files).every(file => !file.missing), files };
}

export async function runSharedActors({ reportDir = resolve(ROOT, "data/reports/shared_city/20261027/shared_actors_attempt01"), engine = ENGINE, ownerGraphics = false } = {}) {
  reportDir = resolve(reportDir); engine = resolve(engine);
  if (reportDir === resolve(ROOT, "game") || reportDir.startsWith(resolve(ROOT, "game") + "/")) throw new Error("Reports must stay outside game resources");
  await access(engine, constants.X_OK);
  await mkdir(dirname(reportDir), { recursive: true });
  await mkdir(reportDir); // Deliberately reject an existing evidence directory.
  const started = Date.now(); const records = [];
  let api, coordinator, timer, signalHandler;
  const record = { task: "EXP41_SHARED_ACTORS", started_at_utc: new Date(started).toISOString(),
    result: "FAIL", timeout_ms: 200_000, timed_out: false, failure: null, source_sha256_before: null, source_sha256_after: null,
    render_modes: { a: ownerGraphics ? "native_graphical" : "headless", b: "headless" },
    scope: "Two independent production explore_walk games exercising 14 shared road cars and 28 adult NPCs + 2 dogs with an independent fake-development loopback API/coordinator. Host AI, approved poses and exclusive vehicle claims; no server physics, production identity, Site/publication, or performance acceptance. Owner graphics is optional and any captures must be labelled fixture views. Root-owned server8766 is untouched." };
  try {
    record.source_sha256_before = await sourceHashes();
    api = await startDevServer({ apiOnly: true, port: 0 });
    record.api_rejections = [];
    api.server.prependListener("request", (incoming, outgoing) => {
      const original = outgoing.end;
      outgoing.end = function (...args) {
        if (outgoing.statusCode >= 400 && args[0]) {
          try {
            const body = JSON.parse(String(args[0])); const details = {};
            for (const key of ["error", "entityId", "kind", "observedDistance", "allowedDistance", "elapsedMs"]) if (body[key] !== undefined) details[key] = body[key];
            record.api_rejections.push({ status: outgoing.statusCode, operation: incoming.url.split("/").at(-1), ...details });
            record.api_rejections = record.api_rejections.slice(-64);
          } catch { /* Diagnostics exclude arbitrary response bodies. */ }
        }
        return original.apply(this, args);
      };
    });
    coordinator = await createCoordinator();
    record.api_origin = api.origin; record.coordinator_origin = coordinator.origin;
    for (const role of ["a", "b"]) records.push(startGame(role, engine, api.origin, coordinator.origin, reportDir, ownerGraphics));
    const allFinished = Promise.all(records.map(child => child.done)).then(async () => {
      for (const child of records) if (!(await summarize(child)).passed) throw new Error(`role_${child.role}_failed`);
    });
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
    record.source_unchanged = record.source_sha256_before !== null && JSON.stringify(record.source_sha256_before) === JSON.stringify(record.source_sha256_after);
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
  const result = await runSharedActors({ ...(values["report-dir"] ? { reportDir: values["report-dir"] } : {}), ...(values.engine ? { engine: values.engine } : {}), ownerGraphics: values["owner-graphics"] });
  console.log(JSON.stringify({ result: result.record.result, report: result.path, elapsed_ms: result.record.elapsed_ms,
    games: result.record.games.map(game => ({ role: game.role, pid: game.pid, exit_code: game.exit_code, error_count: game.error_count, engine_error_count: game.engine_error_count, report_result: game.report_result })) }));
  process.exitCode = result.record.result === "PASS" ? 0 : 1;
}
