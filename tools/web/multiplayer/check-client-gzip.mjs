/** Bounded native HTTPRequest gzip regression; no game scene or Site is used. */
import { createServer } from "node:http";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { createWriteStream, constants } from "node:fs";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { pipeline } from "node:stream/promises";
import { createHash } from "node:crypto";
import { gzipSync, deflateSync } from "node:zlib";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { startDevServer } from "./dev-server.mjs";

const ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const ENGINE = "/Applications/Godot.app/Contents/MacOS/Godot";
const SOURCES = [
  "game/scripts/multiplayer/room_presence_client.gd", "tests/game/check_room_presence_client.gd",
  "tools/web/multiplayer/check-client-gzip.mjs", "tools/web/multiplayer/dev-server.mjs",
  "tools/web/multiplayer/room-api.mjs", "tools/web/multiplayer/local-d1.mjs", "tools/web/multiplayer/schema.sql",
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

export async function createGzipFixture() {
  const json = Buffer.from(JSON.stringify({ available: true, apiVersion: 1, mode: "sites", signInRequired: true }));
  const cases = [
    { name: "native_actual_gzip", encoding: "gzip", body: gzipSync(json, { mtime: 0 }) },
    { name: "native_actual_deflate", encoding: "deflate", body: deflateSync(json) },
    { name: "browser_decoded_gzip_header", encoding: "gzip", body: json },
    { name: "browser_decoded_deflate_header", encoding: "deflate", body: json },
  ];
  const counts = cases.map(() => 0);
  let origin, requests = 0, rejected = 0;
  const server = createServer((incoming, outgoing) => {
    const valid = incoming.socket.remoteAddress === "127.0.0.1" && incoming.headers.host === new URL(origin).host
      && incoming.method === "GET" && incoming.url === "/api/multiplayer/status"
      && !incoming.headers.cookie && !incoming.headers.authorization
      && (!incoming.headers.origin || incoming.headers.origin === origin);
    if (!valid || requests >= cases.length) {
      rejected += 1; incoming.resume();
      outgoing.writeHead(400, { "content-type": "application/json", "cache-control": "no-store" });
      return outgoing.end('{"error":"invalid_fixture_request"}');
    }
    const index = requests++; const item = cases[index]; counts[index] += 1;
    outgoing.writeHead(200, { "content-type": "application/json", "content-encoding": item.encoding,
      "content-length": item.body.length, "cache-control": "no-store", "x-content-type-options": "nosniff" });
    outgoing.end(item.body);
  });
  server.requestTimeout = 5000; server.headersTimeout = 5000;
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  origin = `http://127.0.0.1:${server.address().port}`;
  return { origin, server, summary() {
    return { request_count: requests, rejected_requests: rejected, cases: cases.map((item, index) => ({
      name: item.name, content_encoding: item.encoding, response_bytes: item.body.length, request_count: counts[index],
    })), credentials_recorded: false, complete: requests === 4 && rejected === 0 && counts.every(count => count === 1) };
  }, async close() {
    server.closeAllConnections();
    await new Promise((accept, reject) => server.close(error => error ? reject(error) : accept()));
  } };
}

async function sourceHashes() {
  return Object.fromEntries(await Promise.all(SOURCES.map(async name => [name, digest(await readFile(resolve(ROOT, name)))])));
}
async function artifact(path) {
  try { const bytes = await readFile(path); return { bytes: bytes.length, sha256: digest(bytes) }; } catch { return { missing: true }; }
}
function startEngine(apiOrigin, gzipOrigin, files) {
  const args = ["--headless", "--path", resolve(ROOT, "game"), "--log-file", files.engine,
    "--script", resolve(ROOT, "tests/game/check_room_presence_client.gd"), "--",
    `--base=${apiOrigin}`, `--gzip-base=${gzipOrigin}`, `--report=${files.report}`];
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

export async function runClientGzip({ reportDir = resolve(ROOT, "data/reports/shared_city/20261027/client_gzip01") } = {}) {
  reportDir = resolve(reportDir);
  if (reportDir.startsWith(resolve(ROOT, "game") + "/")) throw new Error("Reports must stay outside game resources");
  await access(ENGINE, constants.X_OK);
  await mkdir(dirname(reportDir), { recursive: true }); await mkdir(reportDir);
  const files = Object.fromEntries(["report", "engine", "stdout", "stderr"].map(name => [name, resolve(reportDir, `client_${name}.${name === "report" ? "json" : "log"}`)]));
  const started = Date.now(); let api, gzip, engine, timer, signalHandler;
  const result = { task: "EXP40_CLIENT_GZIP_TRANSPORT", result: "FAIL", started_at_utc: new Date(started).toISOString(),
    timeout_ms: 45_000, timed_out: false, failure: null, cleanup_errors: [], source_sha256_before: null, source_sha256_after: null,
    scope: "One bounded headless production HTTPRequest fixture with independent in-memory loopback API and four sequential encoding responses. Native gzip/deflate plus already-decoded-body/header browser mimics. No actual browser, city scene, hosted identity, Site request or production compression acceptance. Root8766 is untouched." };
  try {
    result.source_sha256_before = await sourceHashes();
    api = await startDevServer({ apiOnly: true, port: 0 });
    gzip = await createGzipFixture();
    result.api_origin = api.origin; result.gzip_origin = gzip.origin;
    engine = startEngine(api.origin, gzip.origin, files);
    const timeout = new Promise((_, reject) => { timer = setTimeout(() => { result.timed_out = true; reject(new Error("client_fixture_timeout")); }, result.timeout_ms); });
    const interrupted = new Promise((_, reject) => {
      signalHandler = () => reject(new Error("interrupted"));
      process.once("SIGINT", signalHandler); process.once("SIGTERM", signalHandler);
    });
    await Promise.race([engine.done, timeout, interrupted]);
  } catch (error) { result.failure = String(error.message ?? "client_fixture_failed"); }
  finally {
    clearTimeout(timer);
    if (signalHandler) { process.removeListener("SIGINT", signalHandler); process.removeListener("SIGTERM", signalHandler); }
    try { await stopEngine(engine); } catch { result.cleanup_errors.push("engine_cleanup_failed"); }
    if (gzip) { result.gzip_fixture = gzip.summary(); try { await gzip.close(); } catch { result.cleanup_errors.push("gzip_cleanup_failed"); } }
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
      && result.fixture_result === "PASS" && result.gzip_fixture?.complete
      && Object.values(result.error_counts).every(count => count === 0) && Object.values(result.artifacts).every(item => !item.missing);
    result.result = passed ? "PASS" : "FAIL"; result.elapsed_ms = Date.now() - started;
    const path = resolve(reportDir, "summary.json"); await writeFile(path, JSON.stringify(result, null, 2) + "\n");
    return { result, path };
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { "report-dir": { type: "string" } } });
  const output = await runClientGzip({ ...(values["report-dir"] ? { reportDir: values["report-dir"] } : {}) });
  console.log(JSON.stringify({ result: output.result.result, report: output.path, elapsed_ms: output.result.elapsed_ms, engine_exit_code: output.result.engine?.exit_code ?? null }));
  process.exitCode = output.result.result === "PASS" ? 0 : 1;
}
