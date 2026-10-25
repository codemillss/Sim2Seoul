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

function harness({ respond, engineReady = true, missingScript = false, cacheStorage, qualitySearch = "", devicePixelRatio = 1, pointerLock } = {}) {
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
  let engineArgs;
  let context;
  const windowListeners = {};
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
      focus() {}, remove() {}, requestPointerLock: id === "gameCanvas" ? pointerLock : undefined, getContext() { return { getExtension: () => ({ loseContext() {} }) }; },
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
  Engine.prototype.start = async (options) => { engineStarts += 1; engineArgs = options.args; if (engineReady) engineOptions.onPrint("EXPLORATION_READY test=true"); };
  const sandbox = {
    URL, URLSearchParams, Blob, Error, DOMException, Uint8Array, ArrayBuffer, Request, Response, AbortController, CustomEvent,
    TransformStream, ReadableStream, DecompressionStream, WebAssembly, crypto: webcrypto,
    setTimeout: setTimer, clearTimeout: (id) => timers.delete(id),
    requestAnimationFrame: (fn) => queueMicrotask(fn),
    console: { error() {}, info() {}, warn() {} },
    location: { href: `https://game.example/play.html${qualitySearch}`, search: qualitySearch, origin: "https://game.example", reload() {} },
    localStorage: { getItem: () => null, setItem() {} }, caches: cacheStorage,
    fetch: fetchStub, Engine: missingScript ? undefined : Engine,
    document: {
      getElementById: element, querySelector: () => element("toolbar"),
      createElement: (type) => element(`${type}-${elements.size}`),
      head: { appendChild() {} }, addEventListener() {},
    },
    addEventListener(type, fn) { windowListeners[type] = fn; }, dispatchEvent() {}, devicePixelRatio,
  };
  sandbox.window = sandbox;
  context = vm.createContext(sandbox);
  vm.runInContext(source, context, { filename: "game-loader.js" });
  return {
    data, requests, attempts, snapshots, tick, element,
    get qa() { return context.__SIM2SEOUL_WEB_QA; },
    get starts() { return engineStarts; },
    get engineArgs() { return engineArgs; },
    start: async () => { element("startButton").listeners.click(); await flush(); },
    sendReady: () => engineOptions.onPrint("EXPLORATION_READY test=manual"),
    rejectRuntime: (reason) => windowListeners.unhandledrejection({ reason }),
  };
}

const GAME_CACHE = "sim2seoul-verified-assets-v1";
function cacheFixture({ shared = new Map(), faults = {} } = {}) {
  const calls = [];
  const puts = [];
  const urlFor = (key) => key instanceof Request ? key.url : String(key);
  const operation = (name, detail, normal) => {
    calls.push({ operation: name, ...detail });
    const mode = faults[name];
    if (mode === "throw") throw new DOMException(`${name} denied`, "SecurityError");
    if (mode === "reject") return Promise.reject(new DOMException(`${name} quota`, "QuotaExceededError"));
    if (mode === "hang") return never();
    return normal();
  };
  const api = {
    open(name) {
      return operation("open", { name }, () => {
        if (!shared.has(name)) shared.set(name, new Map());
        const entries = shared.get(name);
        return Promise.resolve({
          match(key) { return operation("match", { name, url: urlFor(key) }, () => Promise.resolve(entries.has(urlFor(key)) ? new Response(entries.get(urlFor(key))) : undefined)); },
          keys() { return operation("keys", { name }, () => Promise.resolve([...entries.keys()].map((url) => new Request(url)))); },
          delete(key) { return operation("delete", { name, url: urlFor(key) }, () => Promise.resolve(entries.delete(urlFor(key)))); },
          put(key, response) {
            return operation("put", { name, url: urlFor(key) }, async () => {
              const bytes = Buffer.from(await response.arrayBuffer());
              puts.push({ name, url: urlFor(key), bytes }); entries.set(urlFor(key), bytes);
            });
          },
        });
      });
    },
    // These must never be used: only the dedicated game's own cache is owned.
    keys() { throw new Error("Do not enumerate other applications' cache names"); },
    delete() { throw new Error("Do not delete other applications' caches"); },
  };
  return { api, shared, calls, puts };
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

test("cold verified chunks persist and warm boot uses zero chunk network requests", async () => {
  const cache = cacheFixture();
  const cold = harness({ cacheStorage: cache.api }); await cold.start();
  assert.equal(cold.qa.ready, true); assert.equal(cold.qa.verifiedChunks, 42);
  assert.equal(cold.qa.cachedChunks, 0); assert.equal(cold.qa.networkBytes, cold.qa.totalTransferBytes);
  assert.equal(cache.puts.length, 42); assert.equal(cache.shared.get(GAME_CACHE).size, 42);
  for (const put of cache.puts) {
    const path = new URL(put.url).pathname.slice(1);
    assert.deepEqual(put.bytes, cold.data.payloads.get(path).zipped);
    assert.match(path, /^game\/chunks\/(?:wasm|pck)-\d+\.gz$/);
  }
  const warm = harness({ cacheStorage: cache.api, engineReady: false }); await warm.start();
  assert.equal(warm.requests.filter((r) => r.path.includes("/chunks/")).length, 0);
  assert.equal(warm.qa.networkBytes, 0); assert.equal(warm.qa.cachedChunks, 42);
  assert.equal(warm.qa.cachedBytes, warm.qa.totalTransferBytes); assert.equal(warm.qa.downloadedBytes, warm.qa.totalTransferBytes);
  assert.equal(warm.qa.verifiedChunks, 42); assert.equal(warm.starts, 1);
  assert.equal(warm.qa.ready, false); assert.equal(warm.element("loadingOverlay").hidden, false);
  warm.sendReady(); assert.equal(warm.qa.ready, true);
  assert.equal(cache.puts.length, 42, "Warm reads must not rewrite unchanged verified assets");
});

test("warm cache still runs final whole-file SHA before engine", async () => {
  const cache = cacheFixture(); const cold = harness({ cacheStorage: cache.api }); await cold.start();
  const warm = harness({ cacheStorage: cache.api }); warm.data.manifest.files.pck.sha256 = "0".repeat(64);
  await warm.start();
  assert.equal(warm.qa.cachedChunks, 42); assert.equal(warm.qa.verifiedChunks, 42);
  assert.equal(warm.requests.filter((r) => r.path.includes("/chunks/")).length, 0);
  assert.equal(warm.qa.error.code, "HASH"); assert.equal(warm.starts, 0); assert.equal(warm.qa.ready, false);
});

test("cached gzip with valid lengths but wrong SHA is deleted, re-fetched and replaced", async () => {
  const cache = cacheFixture(); const cold = harness({ cacheStorage: cache.api }); await cold.start();
  const target = new URL(cold.data.last, "https://game.example/").href;
  const raw = Buffer.from(cold.data.payloads.get(cold.data.last).raw); raw[144] ^= 1;
  const bad = gzipSync(raw);
  assert.equal(bad.length, cold.data.payloads.get(cold.data.last).zipped.length, "Exercise SHA rejection, not size or gzip rejection");
  cache.shared.get(GAME_CACHE).set(target, bad);
  const warm = harness({ cacheStorage: cache.api }); await warm.start(); await warm.tick(1000);
  assert.equal(warm.qa.ready, true); assert.equal(warm.qa.cachedChunks, 41); assert.equal(warm.qa.verifiedChunks, 42);
  const chunks = warm.requests.filter((r) => r.path.includes("/chunks/"));
  assert.equal(chunks.length, 1); assert.equal(chunks[0].path, warm.data.last); assert.equal(chunks[0].cache, "reload");
  assert.ok(cache.calls.some((call) => call.operation === "delete" && call.url === target));
  assert.ok(warm.qa.logs.some((entry) => /CHUNK_FAILED.*HASH/.test(entry.text)));
  assert.deepEqual(cache.shared.get(GAME_CACHE).get(target), warm.data.payloads.get(warm.data.last).zipped);
  assert.equal(warm.qa.networkBytes, warm.data.payloads.get(warm.data.last).zipped.length);
  assert.equal(warm.qa.downloadedBytes, warm.qa.totalTransferBytes);
});

test("unverified network bytes are never written to persistent cache", async () => {
  const cache = cacheFixture(); let bad;
  const h = harness({ cacheStorage: cache.api, respond: ({ path, data }) => path === data.last ? new Response(bad) : undefined });
  const raw = Buffer.from(h.data.payloads.get(h.data.last).raw); raw[0] ^= 1; bad = gzipSync(raw);
  h.data.manifest.files.pck.chunks.at(-1).transferBytes = bad.length;
  await h.start(); await h.tick(3000);
  assert.equal(h.qa.error.code, "HASH"); assert.equal(h.qa.verifiedChunks, 41); assert.equal(h.starts, 0);
  const target = new URL(h.data.last, "https://game.example/").href;
  assert.ok(!cache.shared.get(GAME_CACHE).has(target));
  assert.ok(cache.puts.every((put) => put.url !== target));
});

test("cache pruning affects only this game's dedicated cache and current manifest", async () => {
  const fixtureData = fixture();
  const current = new URL(fixtureData.last, "https://game.example/").href;
  const stale = "https://game.example/game/chunks/old-release.gz";
  const elsewhere = "https://game.example/private/account.html";
  const unrelated = new Map([[elsewhere, Buffer.from("private account data")]]);
  const shared = new Map([[GAME_CACHE, new Map([[current, fixtureData.payloads.get(fixtureData.last).zipped], [stale, Buffer.from("old game bytes")]])], ["another-application-cache", unrelated]]);
  const cache = cacheFixture({ shared }); const h = harness({ cacheStorage: cache.api }); await h.start();
  assert.equal(h.qa.ready, true); assert.equal(h.qa.cachedChunks, 1);
  assert.equal(shared.get(GAME_CACHE).size, 42); assert.ok(!shared.get(GAME_CACHE).has(stale));
  assert.deepEqual(shared.get("another-application-cache"), unrelated);
  assert.ok(cache.calls.every((call) => call.name === GAME_CACHE));
  assert.deepEqual(cache.calls.filter((call) => call.operation === "delete").map((call) => call.url), [stale]);
  assert.ok(cache.puts.every((put) => put.url.includes("/game/chunks/")));
});

test("cache API denied, quota failures and hangs stay optional for every operation", async () => {
  for (const operation of ["open", "match", "keys", "put", "delete"]) {
    for (const mode of ["throw", "reject", "hang"]) {
      const shared = new Map([[GAME_CACHE, new Map([["https://game.example/game/chunks/old-release.gz", Buffer.from("old")]])]]);
      const cache = cacheFixture({ shared, faults: { [operation]: mode } });
      const h = harness({ cacheStorage: cache.api }); await h.start();
      if (mode === "hang") await h.tick(1500);
      assert.equal(h.qa.ready, true, `${operation}/${mode}: ${JSON.stringify(h.qa.error)}`);
      assert.equal(h.qa.error, null, `${operation}/${mode}`); assert.equal(h.qa.verifiedChunks, 42, `${operation}/${mode}`);
      assert.equal(h.qa.downloadedBytes, h.qa.totalTransferBytes); assert.equal(h.starts, 1);
      assert.equal(h.requests.filter((r) => r.path.includes("/chunks/")).length, 42);
      if (operation === "match") assert.ok(cache.calls.filter((call) => call.operation === "match").length <= 2, "Disable failed cache reads instead of delaying every chunk");
      if (operation === "put") assert.ok(cache.calls.filter((call) => call.operation === "put").length <= 2, "Disable failed cache writes instead of retrying verified chunks");
    }
  }
});

test("web quality selects bounded DPR and passes only game user arguments after --", async () => {
  for (const [quality, cap] of [["fast", 1], ["balanced", 1.25], ["clear", 2]]) {
    const h = harness({ qualitySearch: `?quality=${quality}`, devicePixelRatio: 3 }); await h.start();
    assert.equal(h.qa.quality, quality); assert.equal(h.qa.canvasResize.renderPixelRatio, cap);
    assert.equal(h.qa.canvasResize.maxRenderPixelRatio, cap);
    assert.ok(h.engineArgs.includes("--"));
    assert.deepEqual(Array.from(h.engineArgs.slice(h.engineArgs.indexOf("--") + 1)), [`--web-quality=${quality}`]);
  }
});

test("pointer lock rejection stays local to optional mouse capture", async () => {
  for (const pointerLock of [
    () => Promise.reject(new Error("If you see this error we have a bug. Please report this bug to chromium.")),
    () => { throw new DOMException("Capture unavailable", "NotAllowedError"); },
  ]) {
    const h = harness({ pointerLock }); await h.start();
    await h.element("gameCanvas").requestPointerLock();
    assert.equal(h.qa.ready, true); assert.equal(h.qa.state, "ready");
    assert.equal(h.qa.error, null); assert.ok(h.qa.pointerLockError);
    assert.ok(h.qa.logs.some((entry) => entry.text.startsWith("POINTER_LOCK_UNAVAILABLE:")));
    assert.equal(h.element("errorPanel").hidden, true);
  }
});

test("unrelated runtime rejections still stop the game", async () => {
  const h = harness({ pointerLock: () => Promise.resolve() }); await h.start();
  h.rejectRuntime(new Error("Actual game failure"));
  assert.equal(h.qa.state, "error"); assert.equal(h.qa.error.code, "BROWSER_RUNTIME");
  assert.equal(h.element("errorPanel").hidden, false);
});
