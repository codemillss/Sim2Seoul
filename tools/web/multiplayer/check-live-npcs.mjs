/** Bounded one-full-city live NPC stability run with safe local API diagnostics. */
import { createServer, request as httpRequest } from "node:http";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { createWriteStream, constants } from "node:fs";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { pipeline } from "node:stream/promises";
import { createHash } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { startDevServer } from "./dev-server.mjs";

const ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const ENGINE = "/Applications/Godot.app/Contents/MacOS/Godot";
const SOURCES = [
  "game/project.godot", "tests/game/check_shared_city_live_npcs.gd", "tools/web/multiplayer/check-live-npcs.mjs",
  "game/scripts/explore_walk.gd", "game/scripts/multiplayer/room_presence_client.gd", "game/scripts/multiplayer/shared_city_walk.gd",
  "game/scripts/multiplayer/shared_city_npcs.gd", "game/scripts/multiplayer/shared_city_vehicles.gd", "game/scripts/multiplayer/remote_resident.gd",
  "game/scripts/street_pedestrians.gd", "game/scripts/exploration_pedestrian_avoidance.gd", "game/scripts/neighborhood_population.gd",
  "game/scripts/traffic/vehicle.gd", "game/scripts/traffic/traffic_manager.gd", "game/scripts/drivable_car_service.gd",
  "tools/web/multiplayer/dev-server.mjs", "tools/web/multiplayer/room-api.mjs", "tools/web/multiplayer/local-d1.mjs", "tools/web/multiplayer/schema.sql",
];
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const delay = ms => new Promise(accept => { const timer = setTimeout(accept, ms); timer.unref(); });
const SECRET_PATTERNS = [
  /Bearer\s+[A-Za-z0-9._~+\/-]+/i,
  /sim2seoul_dev_\d+=[a-f0-9]{64}/i,
  /["']sessionToken["']\s*:\s*["'][a-f0-9]{48}["']/i,
  /\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.[0-9a-f]{32}\b/i,
  /(?<![a-f0-9])[a-f0-9]{48}(?![a-f0-9])/i,
];

export async function createDiagnosticProxy(apiOrigin) {
  let origin; let requestCount = 0, worldSyncs = 0; const statuses = {}; const failures = []; const live = new Set();
  const server = createServer(async (incoming, outgoing) => {
    const deny = (status, error) => { incoming.resume(); outgoing.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" }); outgoing.end(JSON.stringify({ error })); };
    if (incoming.socket.remoteAddress !== "127.0.0.1" || incoming.headers.host !== new URL(origin).host
      || !["GET", "POST"].includes(incoming.method) || !/^\/api\/multiplayer\/[A-Za-z0-9/_-]+$/.test(incoming.url)
      || (incoming.headers.origin && incoming.headers.origin !== origin)) return deny(403, "local_fixture_only");
    try {
      let size = 0; const parts = [];
      for await (const part of incoming) { size += part.length; if (size > 48 * 1024) return deny(413, "body_too_large"); parts.push(part); }
      const bytes = Buffer.concat(parts); requestCount += 1;
      if (incoming.method === "POST") {
        try { const data = JSON.parse(bytes); if (data.world?.entities?.length === 44) worldSyncs += 1; } catch { /* API validates the original bytes. */ }
      }
      const headers = { ...incoming.headers, host: new URL(apiOrigin).host, origin: apiOrigin, "content-length": bytes.length };
      delete headers.connection; delete headers["transfer-encoding"];
      const upstream = httpRequest(new URL(incoming.url, apiOrigin), { method: incoming.method, headers, timeout: 8000 }, response => {
        let length = 0; const chunks = [];
        response.on("data", chunk => { length += chunk.length; if (length > 512 * 1024) { response.destroy(); return; } chunks.push(chunk); });
        response.on("end", () => {
          live.delete(upstream); const body = Buffer.concat(chunks); const status = response.statusCode ?? 502;
          statuses[status] = (statuses[status] ?? 0) + 1;
          if (status === 422 && failures.length < 32) {
            const diagnostic = { status, operation: incoming.url.split("/").at(-1) };
            try {
              const data = JSON.parse(body);
              if (typeof data.error === "string" && /^[a-z0-9_]{1,80}$/.test(data.error)) diagnostic.error = data.error;
              if (typeof data.entityId === "string" && /^[A-Za-z0-9:_-]{1,96}$/.test(data.entityId)) diagnostic.entityId = data.entityId;
              if (["vehicle", "npc", "dog"].includes(data.kind)) diagnostic.kind = data.kind;
              for (const key of ["observedDistance", "allowedDistance", "elapsedMs"]) if (Number.isFinite(data[key])) diagnostic[key] = data[key];
            } catch { diagnostic.error = "invalid_error_body"; }
            failures.push(diagnostic);
          }
          const responseHeaders = { ...response.headers, "content-length": body.length, "cache-control": "no-store" };
          delete responseHeaders.connection; delete responseHeaders["transfer-encoding"];
          outgoing.writeHead(status, responseHeaders); outgoing.end(body);
        });
        response.on("error", () => { live.delete(upstream); if (!outgoing.headersSent) deny(502, "fixture_upstream_failed"); else outgoing.destroy(); });
      });
      live.add(upstream); upstream.on("timeout", () => upstream.destroy());
      upstream.on("error", () => { live.delete(upstream); if (!outgoing.headersSent) deny(502, "fixture_upstream_failed"); else outgoing.destroy(); });
      upstream.end(bytes);
    } catch { if (!outgoing.headersSent) deny(400, "fixture_request_failed"); else outgoing.destroy(); }
  });
  server.requestTimeout = 10000; server.headersTimeout = 10000;
  server.listen(0, "127.0.0.1"); await once(server, "listening"); origin = `http://127.0.0.1:${server.address().port}`;
  return { origin, server, summary() { return { requests: requestCount, full_44_world_requests: worldSyncs, statuses, failures_422: [...failures], credentials_recorded: false, complete: worldSyncs >= 100 && failures.length === 0 }; }, async close() {
    for (const request of live) request.destroy(); live.clear(); server.closeAllConnections();
    await new Promise((accept, reject) => server.close(error => error ? reject(error) : accept()));
  } };
}

async function sourceHashes() {
  return Object.fromEntries(await Promise.all(SOURCES.map(async name => [name, digest(await readFile(resolve(ROOT, name)))])));
}
async function artifact(path) {
  try { const bytes = await readFile(path); return { bytes: bytes.length, sha256: digest(bytes) }; } catch { return { missing: true }; }
}
function startEngine(apiOrigin, proxyOrigin, files) {
  const args = ["--headless", "--path", resolve(ROOT, "game"), "--log-file", files.engine,
    "--script", resolve(ROOT, "tests/game/check_shared_city_live_npcs.gd"), "--",
    `--room-server=${proxyOrigin}`, `--report=${files.report}`];
  const child = spawn(ENGINE, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
  const record = { child, pid: child.pid ?? null, command: [ENGINE, ...args], exited: false, exit_code: null, signal: null, spawn_error: null };
  const closed = new Promise(accept => {
    child.once("error", error => { record.spawn_error = error.code ?? "spawn_failed"; });
    child.once("close", (code, signal) => { record.exited = true; record.exit_code = code; record.signal = signal; accept(); });
  });
  record.done = Promise.all([closed, pipeline(child.stdout, createWriteStream(files.stdout)), pipeline(child.stderr, createWriteStream(files.stderr))]);
  return record;
}
async function stopEngine(record) {
  if (!record) return;
  if (!record.exited && record.pid) record.child.kill("SIGTERM");
  await Promise.race([record.done.catch(() => {}), delay(1500)]);
  if (!record.exited && record.pid) record.child.kill("SIGKILL");
  await Promise.race([record.done.catch(() => {}), delay(3000)]);
}

export async function runLiveNPCs({ reportDir = resolve(ROOT, "data/reports/shared_city/20261027/live_npcs_attempt01") } = {}) {
  reportDir = resolve(reportDir);
  if (reportDir.startsWith(resolve(ROOT, "game") + "/")) throw new Error("Reports must stay outside game resources");
  await access(ENGINE, constants.X_OK);
  await mkdir(dirname(reportDir), { recursive: true }); await mkdir(reportDir);
  const files = Object.fromEntries(["report", "engine", "stdout", "stderr"].map(name => [name, resolve(reportDir, `client_${name}.${name === "report" ? "json" : "log"}`)]));
  const started = Date.now(); let api, proxy, engine, timer, signalHandler;
  const result = { task: "EXP41_LIVE_HOST_NPC_STABILITY", result: "FAIL", started_at_utc: new Date(started).toISOString(),
    timeout_ms: 200_000, timed_out: false, failure: null, cleanup_errors: [], source_sha256_before: null, source_sha256_after: null,
    scope: "One actual full headless city owner with native NPC and AI traffic running for120seconds, full44 entity updates through an independent loopback memory API and safe422 diagnostics proxy. No manual drive, guest, GUI, Site, production identity or performance acceptance. Root8766 is untouched." };
  try {
    result.source_sha256_before = await sourceHashes();
    api = await startDevServer({ apiOnly: true, port: 0 });
    proxy = await createDiagnosticProxy(api.origin);
    result.api_origin = api.origin; result.proxy_origin = proxy.origin;
    engine = startEngine(api.origin, proxy.origin, files);
    const timeout = new Promise((_, reject) => { timer = setTimeout(() => { result.timed_out = true; reject(new Error("live_npc_timeout")); }, result.timeout_ms); });
    const interrupted = new Promise((_, reject) => {
      signalHandler = () => reject(new Error("interrupted"));
      process.once("SIGINT", signalHandler); process.once("SIGTERM", signalHandler);
    });
    await Promise.race([engine.done, timeout, interrupted]);
  } catch (error) { result.failure = String(error.message ?? "live_npc_failed"); }
  finally {
    clearTimeout(timer);
    if (signalHandler) { process.removeListener("SIGINT", signalHandler); process.removeListener("SIGTERM", signalHandler); }
    try { await stopEngine(engine); } catch { result.cleanup_errors.push("engine_cleanup_failed"); }
    if (proxy) { result.proxy_diagnostics = proxy.summary(); try { await proxy.close(); } catch { result.cleanup_errors.push("proxy_cleanup_failed"); } }
    if (api) { try { api.server.closeAllConnections(); await api.close(); } catch { result.cleanup_errors.push("api_cleanup_failed"); } }
    try { result.source_sha256_after = await sourceHashes(); } catch { result.failure ??= "source_snapshot_unavailable"; }
    result.source_unchanged = result.source_sha256_before !== null && JSON.stringify(result.source_sha256_before) === JSON.stringify(result.source_sha256_after);
    result.engine = engine ? { pid: engine.pid, command: engine.command, exited: engine.exited, exit_code: engine.exit_code, signal: engine.signal, spawn_error: engine.spawn_error } : null;
    result.artifacts = {}; result.error_counts = {}; result.raw_logs_secret_free = true;
    for (const name of Object.keys(files)) {
      result.artifacts[name] = { path: files[name], ...await artifact(files[name]) };
      if (name !== "report" && !result.artifacts[name].missing) {
        const content = await readFile(files[name], "utf8");
        result.error_counts[name] = (content.match(/(?:SCRIPT )?ERROR:/g) ?? []).length;
        if (SECRET_PATTERNS.some(pattern => pattern.test(content))) result.raw_logs_secret_free = false;
      }
    }
    try {
      const report = JSON.parse(await readFile(files.report, "utf8"));
      result.fixture_result = report.result; result.fixture_checks = { passed: report.checks - report.failed, total: report.checks, failed: report.failed };
    } catch { result.fixture_result = null; }
    const passed = !result.failure && !result.timed_out && result.cleanup_errors.length === 0 && result.source_unchanged && result.raw_logs_secret_free
      && engine?.exited && engine.exit_code === 0 && !engine.signal && !engine.spawn_error
      && result.fixture_result === "PASS" && result.proxy_diagnostics?.complete
      && Object.values(result.error_counts).every(count => count === 0) && Object.values(result.artifacts).every(item => !item.missing);
    result.result = passed ? "PASS" : "FAIL"; result.elapsed_ms = Date.now() - started;
    const path = resolve(reportDir, "summary.json"); await writeFile(path, JSON.stringify(result, null, 2) + "\n");
    return { result, path };
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { "report-dir": { type: "string" } } });
  const output = await runLiveNPCs({ ...(values["report-dir"] ? { reportDir: values["report-dir"] } : {}) });
  console.log(JSON.stringify({ result: output.result.result, report: output.path, elapsed_ms: output.result.elapsed_ms, engine_exit_code: output.result.engine?.exit_code ?? null }));
  process.exitCode = output.result.result === "PASS" ? 0 : 1;
}
