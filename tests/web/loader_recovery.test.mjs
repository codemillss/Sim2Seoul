/* Executes the shipped loader, real gzip/WebStreams/SHA, and a controlled clock.
 * DOM/engine/network substitutes cover delivery failures, not WebGL gameplay. */
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import { createHash, webcrypto } from "node:crypto";
import { gzipSync } from "node:zlib";
import { test } from "node:test";

const source = await readFile(new URL("../../tools/web/site/game-loader.js", import.meta.url), "utf8");
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
const flush = async () => {
  // Node's real zlib/WebCrypto use worker threads, independent of our fake
  // deadline clock. Yield real event-loop turns without advancing that clock.
  for (let i = 0; i < 500; i += 1) await new Promise((resolve) => i % 25 ? setImmediate(resolve) : setTimeout(resolve, 1));
};
const never = () => new Promise(() => {});

function fixture() {
  const payloads = new Map();
  const files = {};
  for (const [kind, count] of [["wasm", 1], ["pck", 41]]) {
    const all = [];
    const chunks = [];
    for (let i = 0; i < count; i += 1) {
      const raw = Buffer.from(Array.from({ length: 2048 }, (_, j) => (j * 73 + i * 17 + (j >> 4)) % 256));
      const zipped = gzipSync(raw);
      const path = `game/chunks/${kind}-${String(i).padStart(3, "0")}.gz`;
      chunks.push({ path, bytes: raw.length, transferBytes: zipped.length, sha256: sha(raw), encoding: "gzip" });
      payloads.set(path, { raw, zipped }); all.push(raw);
    }
    const raw = Buffer.concat(all);
    files[kind] = { path: `game/index.${kind}`, bytes: raw.length, sha256: sha(raw), chunks };
  }
  return { manifest: { engineVersion: "test", buildCommit: "test-native-base", files }, payloads, last: files.pck.chunks.at(-1).path };
}

function harness({ respond, engineReady = true, missingScript = false } = {}) {
  const data = fixture();
  let now = 0;
  let timerId = 0;
  const timers = new Map();
  const requests = [];
  const attempts = new Map();
  const snapshots = [];
  const elements = new Map();
  let engineOptions;
  let engineStarts = 0;
  let context;
  const setTimer = (fn, delay = 0) => { const id = ++timerId; timers.set(id, { fn, at: now + delay }); return id; };
  const tick = async (ms) => {
    const end = now + ms;
    while (true) {
      const next = [...timers.entries()].filter(([, timer]) => timer.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) break;
      now = next[1].at; timers.delete(next[0]); next[1].fn(); await flush();
    }
    now = end; await flush();
  };
  function element(id) {
    if (elements.has(id)) return elements.get(id);
    let text = "";
    const node = {
      hidden: ["errorPanel", "debugPanel"].includes(id), dataset: {}, listeners: {},
      style: { setProperty() {}, removeProperty() {} }, classList: { add() {}, remove() {} },
      addEventListener(type, fn) { this.listeners[type] = fn; }, setAttribute() {},
      getBoundingClientRect() { return { x: 0, y: id === "gameCanvas" ? 54 : 0, top: id === "gameCanvas" ? 54 : 0, bottom: id === "toolbar" ? 54 : 800, width: 1280, height: id === "gameCanvas" ? 746 : 800 }; },
      focus() {}, remove() {}, getContext() { return { getExtension: () => ({ loseContext() {} }) }; },
      get textContent() { return text; },
      set textContent(value) {
        text = String(value);
        if (id === "debugLog" && context?.__SIM2SEOUL_WEB_QA) {
          const qa = context.__SIM2SEOUL_WEB_QA;
          snapshots.push({ last: text.split("\n").at(-1), downloaded: qa.downloadedBytes, verified: qa.verifiedChunks });
        }
      },
    };
    elements.set(id, node); return node;
  }
  const fetchStub = async (input, options = {}) => {
    const path = new URL(String(input)).pathname.slice(1);
    const attempt = (attempts.get(path) || 0) + 1; attempts.set(path, attempt);
    requests.push({ path, attempt, cache: options.cache, signal: options.signal });
    const override = respond?.({ path, attempt, data, options });
    if (override !== undefined) return override;
    if (path === "game/manifest.json") return Response.json(data.manifest);
    if (path === "game/engine-config.json") return Response.json({ args: [] });
    const payload = data.payloads.get(path);
    assert.ok(payload, `Unexpected request ${path}`);
    return new Response(payload.zipped, { headers: { "Content-Type": "application/gzip" } });
  };
  function Engine(options) { engineOptions = options; }
  Engine.prototype.init = async () => {};
  Engine.prototype.preloadFile = async (bytes, path) => { assert.ok(bytes instanceof ArrayBuffer); assert.equal(path, "index.pck"); };
  Engine.prototype.start = async () => { engineStarts += 1; if (engineReady) engineOptions.onPrint("EXPLORATION_READY test=true"); };
  const sandbox = {
    URL, Error, DOMException, Uint8Array, ArrayBuffer, Request, Response, AbortController, CustomEvent,
    TransformStream, ReadableStream, DecompressionStream, WebAssembly, crypto: webcrypto,
    setTimeout: setTimer, clearTimeout: (id) => timers.delete(id),
    requestAnimationFrame: (fn) => queueMicrotask(fn),
    console: { error() {}, info() {}, warn() {} },
    location: { href: "https://game.example/play.html", origin: "https://game.example", reload() {} },
    fetch: fetchStub, Engine: missingScript ? undefined : Engine,
    document: {
      getElementById: element, querySelector: () => element("toolbar"),
      createElement: (type) => element(`${type}-${elements.size}`),
      head: { appendChild() {} }, addEventListener() {},
    },
    addEventListener() {}, dispatchEvent() {}, devicePixelRatio: 1,
  };
  sandbox.window = sandbox;
  context = vm.createContext(sandbox);
  vm.runInContext(source, context, { filename: "game-loader.js" });
  return {
    data, requests, attempts, snapshots, tick, element,
    get qa() { return context.__SIM2SEOUL_WEB_QA; },
    get starts() { return engineStarts; },
    start: async () => { element("startButton").listeners.click(); await flush(); },
    sendReady: () => engineOptions.onPrint("EXPLORATION_READY test=manual"),
  };
}

function assertOtherChunksOnce(h) {
  for (const path of h.data.payloads.keys()) if (path !== h.data.last) assert.equal(h.attempts.get(path), 1, path);
}

test("last of 42 headers may never settle even after abort; only that chunk retries", async () => {
  const h = harness({ respond: ({ path, attempt, data }) => path === data.last && attempt === 1 ? never() : undefined });
  await h.start();
  assert.equal(h.qa.verifiedChunks, 41); assert.equal(h.qa.ready, false);
  assert.equal(h.element("loadingOverlay").hidden, false);
  assert.match(h.element("loadHint").textContent, /pck-040.gz.*1\/3/);
  await h.tick(29999); assert.equal(h.attempts.get(h.data.last), 1);
  await h.tick(1);
  assert.equal(h.qa.ready, false); assert.equal(h.attempts.get(h.data.last), 1);
  await h.tick(1000);
  assert.equal(h.qa.ready, true); assert.equal(h.qa.verifiedChunks, 42);
  assert.equal(h.qa.downloadedBytes, h.qa.totalTransferBytes);
  assert.equal(h.attempts.get(h.data.last), 2); assertOtherChunksOnce(h);
  assert.equal(h.requests.filter((r) => r.path === h.data.last)[1].cache, "reload");
});

test("partial final body and cancel both never settle; three bounded attempts stop honestly", async () => {
  const h = harness({ respond: ({ path, data }) => {
    if (path !== data.last) return undefined;
    return new Response(new ReadableStream({
      start(controller) { const bytes = data.payloads.get(path).zipped; controller.enqueue(bytes.subarray(0, Math.floor(bytes.length / 2))); },
      cancel: never,
    }), { headers: { "Content-Type": "application/gzip" } });
  } });
  await h.start();
  const baseline = h.qa.totalTransferBytes - h.data.payloads.get(h.data.last).zipped.length;
  assert.ok(h.qa.downloadedBytes > baseline);
  await h.tick(93000); // 3 x 30s idle windows + 1s and 2s retry delays.
  assert.equal(h.attempts.get(h.data.last), 3); assertOtherChunksOnce(h);
  assert.equal(h.qa.error.code, "REQUEST_TIMEOUT"); assert.equal(h.qa.ready, false);
  assert.equal(h.qa.verifiedChunks, 41); assert.equal(h.qa.downloadedBytes, baseline);
  assert.equal(h.element("errorPanel").hidden, false); assert.equal(h.element("loadingSpinner").hidden, true);
  assert.match(h.element("loadHint").textContent, /멈췄습니다/);
  assert.equal(h.qa.pendingChunks.length, 0);
  const retries = h.snapshots.filter((item) => item.last.includes("CHUNK_RETRY"));
  assert.equal(retries.length, 2); assert.ok(retries.every((item) => item.downloaded === baseline && item.verified === 41));
  assert.ok(h.snapshots.every((item) => item.downloaded <= h.qa.totalTransferBytes));
  assert.equal(h.starts, 0);
});

test("HTTP 500 HTML is a transient delivery error, not a login response", async () => {
  const h = harness({ respond: ({ path, attempt, data }) => path === data.last && attempt === 1 ? new Response("upstream error", { status: 500, headers: { "Content-Type": "text/html" } }) : undefined });
  await h.start();
  assert.equal(h.attempts.get(h.data.last), 1); assert.equal(h.qa.ready, false);
  await h.tick(1000);
  assert.equal(h.qa.ready, true); assert.equal(h.attempts.get(h.data.last), 2); assertOtherChunksOnce(h);
  assert.ok(h.qa.logs.some((entry) => /CHUNK_FAILED.*HTTP/.test(entry.text)));
});

test("body idle deadline resets on real compressed-byte progress", async () => {
  let body;
  const h = harness({ respond: ({ path, data }) => path === data.last ? new Response(new ReadableStream({ start(controller) { body = controller; } })) : undefined });
  await h.start(); assert.equal(h.qa.verifiedChunks, 41);
  const bytes = h.data.payloads.get(h.data.last).zipped;
  const half = Math.floor(bytes.length / 2);
  await h.tick(29000); body.enqueue(bytes.subarray(0, half)); await h.tick(0);
  await h.tick(29000); assert.equal(h.attempts.get(h.data.last), 1); assert.equal(h.qa.ready, false);
  body.enqueue(bytes.subarray(half)); body.close(); await h.tick(0);
  assert.equal(h.qa.ready, true); assert.equal(h.qa.downloadedBytes, h.qa.totalTransferBytes);
});

test("valid gzip with corrupted raw hash exhausts retries without verifying it", async () => {
  let zipped;
  const h = harness({ respond: ({ path, data }) => {
    if (path !== data.last) return undefined;
    return new Response(zipped, { headers: { "Content-Type": "application/gzip" } });
  } });
  const raw = Buffer.from(h.data.payloads.get(h.data.last).raw); raw[0] ^= 1;
  zipped = gzipSync(raw);
  h.data.manifest.files.pck.chunks.at(-1).transferBytes = zipped.length;
  await h.start();
  await h.tick(3000);
  assert.equal(h.attempts.get(h.data.last), 3); assertOtherChunksOnce(h);
  assert.equal(h.qa.error.code, "HASH"); assert.equal(h.qa.verifiedChunks, 41);
  assert.equal(h.qa.downloadedBytes, h.qa.totalTransferBytes - h.data.manifest.files.pck.chunks.at(-1).transferBytes);
  assert.equal(h.starts, 0);
});

test("transfer length and decompressed length remain enforced", async () => {
  for (const kind of ["TRANSFER_SIZE", "CHUNK_SIZE"]) {
    let shortGzip;
    const h = harness({ respond: ({ path, data }) => {
      if (path !== data.last) return undefined;
      if (kind === "TRANSFER_SIZE") return new Response(Buffer.concat([data.payloads.get(path).zipped, Buffer.from([0])]));
      return new Response(shortGzip);
    } });
    shortGzip = gzipSync(h.data.payloads.get(h.data.last).raw.subarray(0, 1000));
    if (kind === "CHUNK_SIZE") h.data.manifest.files.pck.chunks.at(-1).transferBytes = shortGzip.length;
    await h.start();
    await h.tick(3000);
    assert.equal(h.qa.error.code, kind); assert.equal(h.attempts.get(h.data.last), 3);
    // Size errors can finish before the other worker verifies its in-flight
    // penultimate chunk; cancellation may therefore leave 40 or 41 verified.
    assert.ok(h.qa.verifiedChunks >= 40 && h.qa.verifiedChunks <= 41); assert.equal(h.qa.ready, false);
  }
});

test("whole-file SHA still blocks engine even when every chunk SHA passes", async () => {
  const h = harness(); h.data.manifest.files.pck.sha256 = "0".repeat(64);
  await h.start();
  assert.equal(h.qa.verifiedChunks, 42); assert.equal(h.qa.error.code, "HASH");
  assert.equal(h.starts, 0); assert.equal(h.qa.ready, false);
});

test("successful HTML auth redirect stops with login advice and no gzip retries", async () => {
  const h = harness({ respond: ({ path, data }) => path === data.last ? new Response("<html>Sign in</html>", { headers: { "Content-Type": "text/html" } }) : undefined });
  await h.start();
  assert.equal(h.qa.error.code, "AUTH"); assert.equal(h.attempts.get(h.data.last), 1);
  assert.match(h.element("errorAdvice").textContent, /로그인/); assert.equal(h.starts, 0);
});

test("metadata headers and bodies have finite deadlines", async () => {
  for (const stage of ["headers", "body"]) {
    const h = harness({ respond: ({ path }) => {
      if (path !== "game/manifest.json") return undefined;
      return stage === "headers" ? never() : new Response(new ReadableStream({ cancel: never }), { headers: { "Content-Type": "application/json" } });
    } });
    await h.start(); assert.equal(h.qa.ready, false);
    await h.tick(30000); assert.equal(h.qa.error.code, "REQUEST_TIMEOUT"); assert.equal(h.starts, 0);
  }
});

test("engine script has a finite deadline after all chunks finish", async () => {
  const h = harness({ missingScript: true });
  await h.start(); assert.equal(h.qa.verifiedChunks, 42); assert.equal(h.qa.ready, false);
  await h.tick(30000); assert.equal(h.qa.error.code, "SCRIPT_LOAD"); assert.equal(h.starts, 0);
});

test("peer request ignored abort is detached when another request fails auth", async () => {
  const h = harness({ respond: ({ path }) => {
    if (path === "game/chunks/wasm-000.gz") return never();
    if (path === "game/chunks/pck-000.gz") return new Response("Login", { status: 401 });
    return undefined;
  } });
  await h.start();
  assert.equal(h.qa.error.code, "AUTH"); assert.equal(h.qa.pendingChunks.length, 0);
  assert.equal(h.qa.verifiedChunks, 0); assert.equal(h.qa.ready, false);
  assert.equal(h.requests.filter((r) => r.path.includes("/chunks/")).length, 2);
  await h.tick(90000); assert.equal(h.qa.error.code, "AUTH"); assert.equal(h.starts, 0);
});

test("download and engine start alone never fake EXPLORATION_READY", async () => {
  const h = harness({ engineReady: false });
  await h.start();
  assert.equal(h.starts, 1); assert.equal(h.qa.state, "starting"); assert.equal(h.qa.ready, false);
  assert.equal(h.element("loadingOverlay").hidden, false);
  h.sendReady(); assert.equal(h.qa.ready, true); assert.equal(h.element("loadingOverlay").hidden, true);
});

test("optional web release distinguishes frontend from native base commit", async () => {
  const h = harness(); h.data.manifest.webRelease = "20261025-recovery01";
  await h.start();
  assert.equal(h.qa.webRelease, "20261025-recovery01");
  assert.match(h.element("buildInfo").textContent, /원본 test-native-.*웹 20261025-recovery01/);
});
