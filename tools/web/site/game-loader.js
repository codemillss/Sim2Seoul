/* Sim2Seoul's actual Godot export. No substitute scene or simulated progress. */
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const ui = {
    shell: $("gameShell"), canvas: $("gameCanvas"), overlay: $("loadingOverlay"),
    title: $("loadingTitle"), description: $("loadingDescription"), start: $("startButton"),
    spinner: $("loadingSpinner"), panel: $("downloadPanel"), phase: $("phaseLabel"),
    percent: $("progressPercent"), progress: $("downloadProgress"), bytes: $("downloadBytes"),
    verified: $("verifyCount"), hint: $("loadHint"), error: $("errorPanel"),
    errorTitle: $("errorTitle"), errorMessage: $("errorMessage"), advice: $("errorAdvice"),
    debug: $("debugPanel"), log: $("debugLog"), build: $("buildInfo"), status: $("gameStatus"),
  };
  const siteBase = new URL("./", location.href);
  const qa = window.__SIM2SEOUL_WEB_QA = {
    state: "idle", ready: false, readySignal: null, error: null,
    engineVersion: null, buildCommit: null, downloadedBytes: 0, totalTransferBytes: 0,
    verifiedChunks: 0, totalChunks: 0, engineErrorCount: 0, logs: [],
    startedAt: null, readyAt: null, fetchAdapterActive: false,
  };
  let started = false;
  let failed = false;
  let aborter = null;
  let readyTimer = null;
  let quietTimer = null;
  let renderQueued = false;
  let canvasResizeQueued = false;

  function resizeCanvas() {
    canvasResizeQueued = false;
    const toolbar = document.querySelector(".play-toolbar");
    const shellRect = ui.shell.getBoundingClientRect();
    const toolbarBottom = toolbar ? toolbar.getBoundingClientRect().bottom : shellRect.top + 54;
    const toolbarHeight = Math.max(0, toolbarBottom - shellRect.top);
    ui.shell.style.setProperty("--game-toolbar-height", `${toolbarHeight}px`);
    // Layout belongs to CSS, including the reserved toolbar space. Policy0
    // leaves it alone; remove any stale full-window inline placement.
    for (const property of ["position", "top", "left", "width", "height"]) ui.canvas.style.removeProperty(property);
    const rect = ui.canvas.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;
    const deviceRatio = window.devicePixelRatio || 1;
    const renderRatio = Math.min(2, Math.max(1, deviceRatio));
    const width = Math.max(1, Math.round(rect.width * renderRatio));
    const height = Math.max(1, Math.round(rect.height * renderRatio));
    if (ui.canvas.width !== width) ui.canvas.width = width;
    if (ui.canvas.height !== height) ui.canvas.height = height;
    qa.canvasResize = {
      policy: 0, cssRect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
      intrinsicWidth: ui.canvas.width, intrinsicHeight: ui.canvas.height,
      devicePixelRatio: deviceRatio, renderPixelRatio: renderRatio, maxRenderPixelRatio: 2,
      toolbarBottom, toolbarDoesNotOverlap: rect.top >= toolbarBottom - 0.5,
      aspectError: Math.abs(width / height - rect.width / rect.height),
    };
  }

  function scheduleCanvasResize() {
    if (!canvasResizeQueued) { canvasResizeQueued = true; requestAnimationFrame(resizeCanvas); }
  }

  class LoadError extends Error {
    constructor(code, message, detail = "") {
      super(message); this.name = "LoadError"; this.code = code; this.detail = detail;
    }
  }

  function setState(state, label) {
    if (failed && state !== "error") return;
    qa.state = state;
    ui.shell.dataset.gameState = state;
    if (label) ui.phase.textContent = label;
    window.dispatchEvent(new CustomEvent("sim2seoul-state", { detail: { state, ready: qa.ready } }));
  }

  function log(message, level = "info") {
    const line = String(message).slice(0, 800);
    qa.logs.push({ level, text: line });
    if (qa.logs.length > 80) qa.logs.splice(0, qa.logs.length - 80);
    ui.log.textContent = qa.logs.map((entry) => `[${entry.level}] ${entry.text}`).join("\n");
    ui.log.scrollTop = ui.log.scrollHeight;
  }

  function showStatus(message, quietAfter = 0) {
    clearTimeout(quietTimer);
    ui.status.textContent = message; ui.status.classList.remove("is-quiet");
    if (quietAfter) quietTimer = setTimeout(() => ui.status.classList.add("is-quiet"), quietAfter);
  }

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes)) return "—";
    if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(2)} GB`;
    if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
    return `${(bytes / 1024).toFixed(0)} KB`;
  }

  function renderProgress() {
    renderQueued = false;
    ui.progress.max = Math.max(qa.totalTransferBytes, 1);
    ui.progress.value = qa.downloadedBytes;
    const pct = qa.totalTransferBytes ? Math.min(100, qa.downloadedBytes / qa.totalTransferBytes * 100) : 0;
    ui.percent.textContent = `${pct.toFixed(0)}%`;
    ui.bytes.textContent = `${formatBytes(qa.downloadedBytes)} / ${formatBytes(qa.totalTransferBytes)}`;
    ui.verified.textContent = `자료 확인 ${qa.verifiedChunks}/${qa.totalChunks}`;
  }

  function queueProgress() {
    if (!renderQueued) { renderQueued = true; requestAnimationFrame(renderProgress); }
  }

  function fail(error) {
    if (failed) return;
    failed = true; qa.ready = false;
    clearTimeout(readyTimer);
    if (aborter) aborter.abort();
    const code = error.code || error.name || "UNKNOWN";
    const reason = error.detail || error.message || String(error);
    const stack = error.stack ? String(error.stack) : "";
    const detail = stack ? `${reason}\n${stack}` : reason;
    qa.error = { code, message: error.message || "실행 중 문제가 발생했습니다.", detail, phase: qa.state };
    setState("error", "실행을 멈췄습니다");
    ui.overlay.hidden = false; ui.spinner.hidden = true; ui.start.hidden = true;
    ui.error.hidden = false; ui.debug.open = true;
    ui.title.textContent = "도시를 열지 못했습니다.";
    ui.description.textContent = "아래 안내를 확인한 뒤 다시 시도해 주세요.";
    ui.errorMessage.textContent = error.message || "게임 자료를 준비하는 중 문제가 발생했습니다.";
    ui.advice.textContent = adviceFor(code);
    log(`${code}: ${detail}`, "error");
    console.error("[Sim2Seoul]", code, detail);
  }

  function adviceFor(code) {
    if (["WEBGL2", "WASM", "DECOMPRESSION", "WEB_CRYPTO", "FEATURES"].includes(code)) {
      return "최신 Chrome 또는 Edge에서 열어 주세요. WebGL 2와 하드웨어 가속을 켜고, HTTPS 주소로 접속해야 합니다.";
    }
    if (["NETWORK", "HTTP", "MANIFEST", "CONFIG", "SCRIPT_LOAD"].includes(code)) {
      return "네트워크 연결을 확인한 뒤 다시 시도하세요. 계속 같다면 배포된 게임 자료가 빠졌을 수 있습니다. 아래 실행 정보를 함께 전달해 주세요.";
    }
    if (["HASH", "CHUNK_SIZE", "TRANSFER_SIZE"].includes(code)) {
      return "다운로드 자료가 배포 기록과 다릅니다. 오래된 탭을 닫고 다시 시도하세요. 반복되면 배포 자료를 확인해야 합니다.";
    }
    if (code === "READY_TIMEOUT") return "도시 준비 응답이 오래 걸리고 있습니다. 다른 무거운 탭을 닫고 다시 시도하세요. 이 기록만으로 로딩 성능이나 실행 성공을 판단하지 않습니다.";
    if (code === "MEMORY" || code === "RangeError") return "브라우저 메모리가 부족할 수 있습니다. 다른 탭을 닫은 뒤 PC의 최신 브라우저에서 다시 시도하세요.";
    return "다시 실행해도 같다면 아래 실행 정보의 마지막 메시지를 함께 전달해 주세요. 게임 오류가 발생한 상태에서는 준비 완료로 표시하지 않습니다.";
  }

  function assertAvailableFeatures() {
    if (typeof WebAssembly !== "object") throw new LoadError("WASM", "이 브라우저는 게임 실행에 필요한 WebAssembly를 지원하지 않습니다.");
    if (typeof DecompressionStream !== "function") throw new LoadError("DECOMPRESSION", "이 브라우저는 게임 자료 압축 해제를 지원하지 않습니다.");
    if (!window.crypto?.subtle) throw new LoadError("WEB_CRYPTO", "게임 자료를 안전하게 확인할 수 없습니다. HTTPS 주소로 접속해 주세요.");
    const probe = document.createElement("canvas");
    const gl = probe.getContext("webgl2");
    if (!gl) throw new LoadError("WEBGL2", "WebGL 2를 사용할 수 없어 3D 도시를 열 수 없습니다.");
    gl.getExtension("WEBGL_lose_context")?.loseContext();
  }

  function assetURL(path) {
    if (typeof path !== "string" || !path || path.includes("\\") || /^[a-z]+:/i.test(path)) throw new LoadError("MANIFEST", "게임 자료 경로가 올바르지 않습니다.", String(path));
    const url = new URL(path, siteBase);
    if (url.origin !== location.origin || !url.pathname.startsWith(siteBase.pathname) || url.search || url.hash) throw new LoadError("MANIFEST", "게임 자료가 이 사이트 밖의 경로를 가리킵니다.", path);
    return url;
  }

  async function fetchResponse(url) {
    let response;
    try { response = await fetch(url, { signal: aborter.signal, credentials: "same-origin" }); }
    catch (error) {
      if (error.name === "AbortError") throw error;
      throw new LoadError("NETWORK", "게임 자료에 연결하지 못했습니다.", `${url}: ${error.message}`);
    }
    if (!response.ok) throw new LoadError("HTTP", `게임 자료 요청이 실패했습니다 (${response.status}).`, String(url));
    return response;
  }

  async function fetchJSON(path, code) {
    const response = await fetchResponse(assetURL(path));
    try { return await response.json(); }
    catch { throw new LoadError(code, "게임 배포 정보를 읽을 수 없습니다.", path); }
  }

  function validBytes(value) { return Number.isSafeInteger(value) && value > 0; }
  function validHash(value) { return typeof value === "string" && /^[a-f0-9]{64}$/i.test(value); }

  function validateManifest(manifest) {
    if (!manifest || typeof manifest.engineVersion !== "string" || typeof manifest.buildCommit !== "string" || !manifest.files) throw new LoadError("MANIFEST", "게임 배포 정보의 형식이 올바르지 않습니다.");
    const files = [];
    for (const kind of ["wasm", "pck"]) {
      const file = manifest.files[kind];
      const expectedPath = `game/index.${kind}`;
      if (!file || file.path !== expectedPath || !validBytes(file.bytes) || !validHash(file.sha256) || !Array.isArray(file.chunks) || !file.chunks.length) throw new LoadError("MANIFEST", "필수 게임 자료의 기록이 올바르지 않습니다.", kind);
      assetURL(file.path);
      let offset = 0;
      const chunks = file.chunks.map((chunk, index) => {
        if (!chunk || chunk.encoding !== "gzip" || !validBytes(chunk.bytes) || !validBytes(chunk.transferBytes) || !validHash(chunk.sha256)) throw new LoadError("MANIFEST", "압축 자료의 크기나 확인 값이 잘못되었습니다.", `${kind}/${index}`);
        const result = { ...chunk, url: assetURL(chunk.path), offset, kind, index };
        offset += chunk.bytes;
        if (!Number.isSafeInteger(offset)) throw new LoadError("MANIFEST", "게임 자료 크기가 유효 범위를 벗어났습니다.");
        return result;
      });
      if (offset !== file.bytes) throw new LoadError("MANIFEST", "자료 조각의 합계와 게임 파일 크기가 다릅니다.", kind);
      files.push({ ...file, kind, chunks, buffer: null });
    }
    const paths = files.flatMap((file) => file.chunks.map((chunk) => chunk.url.href));
    if (new Set(paths).size !== paths.length) throw new LoadError("MANIFEST", "배포 정보에 중복 자료 경로가 있습니다.");
    return files;
  }

  async function checkHash(bytes, expected, label) {
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    const actual = Array.from(new Uint8Array(digest), (n) => n.toString(16).padStart(2, "0")).join("");
    if (actual !== expected.toLowerCase()) throw new LoadError("HASH", "게임 자료의 확인 값이 일치하지 않습니다.", label);
  }

  async function readChunk(file, chunk) {
    const response = await fetchResponse(chunk.url);
    if (!response.body) throw new LoadError("NETWORK", "게임 자료 응답이 비어 있습니다.", chunk.path);
    let transferred = 0;
    const tracked = response.body.pipeThrough(new TransformStream({
      transform(bytes, controller) {
        transferred += bytes.byteLength;
        qa.downloadedBytes += bytes.byteLength; queueProgress();
        controller.enqueue(bytes);
      },
    }));
    const reader = tracked.pipeThrough(new DecompressionStream("gzip")).getReader();
    let written = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (written + value.byteLength > chunk.bytes) throw new LoadError("CHUNK_SIZE", "압축 해제된 자료가 기록보다 큽니다.", chunk.path);
        file.buffer.set(value, chunk.offset + written); written += value.byteLength;
      }
    } catch (error) {
      try { await reader.cancel(); } catch { /* Preserve the original failure. */ }
      if (error instanceof LoadError || error.name === "AbortError") throw error;
      throw new LoadError("CHUNK_SIZE", "게임 자료의 압축을 해제하지 못했습니다.", `${chunk.path}: ${error.message}`);
    } finally { reader.releaseLock(); }
    if (written !== chunk.bytes) throw new LoadError("CHUNK_SIZE", "게임 자료가 완전히 내려받아지지 않았습니다.", chunk.path);
    if (transferred !== chunk.transferBytes) throw new LoadError("TRANSFER_SIZE", "내려받은 자료 크기가 배포 기록과 다릅니다.", `${chunk.path}: ${transferred}/${chunk.transferBytes}`);
    await checkHash(file.buffer.subarray(chunk.offset, chunk.offset + written), chunk.sha256, chunk.path);
    qa.verifiedChunks += 1; queueProgress();
  }

  async function loadFiles(files) {
    const jobs = [];
    try {
      for (const file of files) {
        file.buffer = new Uint8Array(file.bytes);
        for (const chunk of file.chunks) jobs.push({ file, chunk });
      }
    } catch (error) { throw new LoadError("MEMORY", "게임 자료를 담을 메모리를 확보하지 못했습니다.", error.message); }
    qa.totalChunks = jobs.length;
    qa.totalTransferBytes = jobs.reduce((sum, job) => sum + job.chunk.transferBytes, 0);
    renderProgress();
    let cursor = 0;
    // At most two compressed responses/decompressors are active at once.
    const worker = async () => {
      while (cursor < jobs.length && !failed) {
        const job = jobs[cursor++]; await readChunk(job.file, job.chunk);
      }
    };
    await Promise.all([worker(), worker()]);
    setState("verifying", "내려받은 도시 자료 확인 중");
    ui.hint.textContent = "전체 자료가 제작 기록과 같은지 확인하고 있습니다.";
    for (const file of files) await checkHash(file.buffer, file.sha256, file.path);
    renderProgress();
  }

  function loadEngineScript() {
    if (typeof window.Engine === "function") return Promise.resolve();
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = assetURL("game/index.js").href;
      script.onload = () => typeof window.Engine === "function" ? resolve() : reject(new LoadError("SCRIPT_LOAD", "게임 실행기를 읽지 못했습니다."));
      script.onerror = () => reject(new LoadError("SCRIPT_LOAD", "게임 실행기를 내려받지 못했습니다.", script.src));
      document.head.appendChild(script);
    });
  }

  function markReady(line) {
    if (failed || qa.ready) return;
    qa.ready = true; qa.readySignal = line; qa.readyAt = new Date().toISOString();
    clearTimeout(readyTimer); setState("ready", "도시 준비 완료");
    resizeCanvas();
    ui.overlay.hidden = true; ui.spinner.hidden = true;
    ui.canvas.focus({ preventScroll: true });
    showStatus("화면을 클릭해 시작하세요 · WASD 이동 · E 이용 · Esc 메뉴", 14000);
  }

  function enginePrint(...args) {
    const line = args.map(String).join(" "); log(line); console.info("[Godot]", ...args);
    if (/(?:\bSCRIPT ERROR\b|\bParse Error\b|\bERROR:)/i.test(line)) {
      qa.engineErrorCount += 1; fail(new LoadError("ENGINE_OUTPUT", "도시를 준비하는 중 게임 오류가 발생했습니다.", line)); return;
    }
    if (/(?:^|\s)EXPLORATION_READY(?:\s|$)/.test(line)) markReady(line);
  }

  function enginePrintError(...args) {
    const line = args.map(String).join(" ");
    if (!line.trim()) return;
    if (/^\s*WARNING:/i.test(line)) { log(line, "warning"); console.warn("[Godot]", ...args); return; }
    log(line, "error"); console.error("[Godot]", ...args); qa.engineErrorCount += 1;
    fail(new LoadError("ENGINE_OUTPUT", "게임 실행 중 오류가 발생했습니다.", line));
  }

  async function initializeEngine(config, wasm, pck) {
    resizeCanvas();
    const engine = new window.Engine({
      ...config, canvas: ui.canvas, executable: "game/index", mainPack: "index.pck",
      persistentPaths: ["/userfs"], locale: "ko", focusCanvas: true, canvasResizePolicy: 0,
      onPrint: enginePrint, onPrintError: enginePrintError,
      onExit: (code) => fail(new LoadError("ENGINE_EXIT", "게임 실행이 종료되었습니다. 다시 실행할 수 있습니다.", `exit=${code}`)),
    });
    const wasmURL = assetURL(wasm.path).href;
    const previousFetch = window.fetch;
    // Only the official engine's one exact same-origin WASM GET is adapted.
    // No other URL, method or credential behavior is changed. The adapter is
    // restored after init whether init succeeds, rejects, or prints an error.
    const adaptedFetch = function (input, init) {
      const request = input instanceof Request ? input : null;
      const method = String(init?.method || request?.method || "GET").toUpperCase();
      const url = new URL(request ? request.url : String(input), location.href);
      if (method === "GET" && url.origin === location.origin && url.href === wasmURL) {
        return Promise.resolve(new Response(wasm.buffer, { status: 200, headers: { "Content-Type": "application/wasm", "Content-Length": String(wasm.bytes) } }));
      }
      return previousFetch.call(window, input, init);
    };
    window.fetch = adaptedFetch; qa.fetchAdapterActive = true;
    let initTimer;
    try {
      await Promise.race([
        engine.init("game/index"),
        new Promise((_, reject) => { initTimer = setTimeout(() => reject(new LoadError("READY_TIMEOUT", "3D 실행기 준비 응답이 오래 걸리고 있습니다.")), 180000); }),
      ]);
    }
    finally {
      clearTimeout(initTimer);
      if (window.fetch === adaptedFetch) window.fetch = previousFetch;
      qa.fetchAdapterActive = false;
    }
    wasm.buffer = null;
    if (failed) return;
    // The official wrapper indexes fileSizes[file] before preloading. A
    // Uint8Array would coerce its entire contents into a comma-separated key.
    // ArrayBuffer is the documented byte-input API and has no such coercion.
    await engine.preloadFile(pck.buffer.buffer, "index.pck");
    setState("starting", "서울의 거리 준비 중");
    ui.hint.textContent = "게임이 도시와 상호작용을 준비하고 있습니다. 준비 신호가 올 때까지 기다려 주세요.";
    readyTimer = setTimeout(() => fail(new LoadError("READY_TIMEOUT", "도시 준비 응답이 오래 걸리고 있습니다.")), 180000);
    // startGame() would fetch a large PCK URL again. These are the original
    // assembled bytes in Godot's own filesystem, with the actual city entry.
    await engine.start({ args: ["--main-pack", "index.pck", ...(Array.isArray(config.args) ? config.args : [])] });
    resizeCanvas();
    pck.buffer = null;
    log("Engine start() returned; visibility still requires actual EXPLORATION_READY.");
  }

  async function boot() {
    if (started) return;
    started = true; qa.startedAt = new Date().toISOString(); aborter = new AbortController();
    ui.start.disabled = true; ui.start.hidden = true; ui.panel.hidden = false; ui.spinner.hidden = false;
    ui.title.textContent = "서울을 준비하고 있어요.";
    ui.description.textContent = "게임 자료를 내려받고, 원본 기록과 같은지 확인합니다.";
    setState("checking", "브라우저와 게임 정보 확인 중");
    try {
      assertAvailableFeatures();
      const [manifest, config] = await Promise.all([fetchJSON("game/manifest.json", "MANIFEST"), fetchJSON("game/engine-config.json", "CONFIG")]);
      if (!config || typeof config !== "object" || Array.isArray(config)) throw new LoadError("CONFIG", "게임 실행 설정이 올바르지 않습니다.");
      const files = validateManifest(manifest);
      qa.engineVersion = manifest.engineVersion; qa.buildCommit = manifest.buildCommit;
      ui.build.textContent = `Godot ${manifest.engineVersion} · build ${manifest.buildCommit.slice(0, 12)}`;
      setState("downloading", "도시 자료 내려받는 중");
      await Promise.all([loadFiles(files), loadEngineScript()]);
      if (failed) return;
      setState("initializing", "3D 실행기 준비 중");
      ui.hint.textContent = "확인을 마쳤습니다. 브라우저에서 3D 도시를 시작합니다.";
      await initializeEngine(config, files.find((file) => file.kind === "wasm"), files.find((file) => file.kind === "pck"));
    } catch (error) {
      if (error.name !== "AbortError" || !failed) fail(error);
    }
  }

  ui.start.addEventListener("click", boot);
  $("retryButton").addEventListener("click", () => location.reload());
  $("reloadButton").addEventListener("click", () => location.reload());
  $("helpButton").addEventListener("click", () => {
    const panel = $("playHelp"); panel.hidden = !panel.hidden;
    $("helpButton").setAttribute("aria-expanded", String(!panel.hidden));
  });
  $("fullscreenButton").addEventListener("click", async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else if (ui.shell.requestFullscreen) await ui.shell.requestFullscreen();
      else showStatus("이 브라우저는 전체 화면 전환을 지원하지 않습니다.", 7000);
    } catch { showStatus("전체 화면을 열지 못했습니다. 브라우저의 전체 화면 기능을 사용해 주세요.", 7000); }
  });
  document.addEventListener("fullscreenchange", () => { $("fullscreenButton").textContent = document.fullscreenElement ? "화면 복원" : "전체 화면"; scheduleCanvasResize(); });
  window.addEventListener("resize", scheduleCanvasResize);
  if (typeof ResizeObserver === "function") {
    const resizeObserver = new ResizeObserver(scheduleCanvasResize);
    resizeObserver.observe(ui.shell); resizeObserver.observe(ui.canvas);
    const toolbar = document.querySelector(".play-toolbar");
    if (toolbar) resizeObserver.observe(toolbar);
  }
  resizeCanvas();
  ui.canvas.addEventListener("pointerdown", () => ui.canvas.focus({ preventScroll: true }));
  window.addEventListener("error", (event) => { if (started && !failed) fail(new LoadError("BROWSER_RUNTIME", "브라우저에서 실행 오류가 발생했습니다.", event.message || "Script error")); });
  window.addEventListener("unhandledrejection", (event) => { if (started && !failed) fail(new LoadError("BROWSER_RUNTIME", "게임 실행 요청을 완료하지 못했습니다.", event.reason?.message || String(event.reason))); });
})();
