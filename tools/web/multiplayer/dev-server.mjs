/** Loopback-only development host. Does not implement production authentication. */
import { createServer } from "node:http";
import { once } from "node:events";
import { createReadStream } from "node:fs";
import { realpath, stat } from "node:fs/promises";
import { randomBytes, randomUUID } from "node:crypto";
import { extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { createRoomApi, POLICY } from "./room-api.mjs";
import { createLocalD1 } from "./local-d1.mjs";

export const DEV_SESSION = Object.freeze({ lifetimeMs: 60 * 60 * 1000, capacity: 128 });
const PREFIX = "/api/multiplayer/";
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8", ".gz": "application/gzip", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".txt": "text/plain; charset=utf-8", ".md": "text/plain; charset=utf-8" };
const STATIC = [
  /^\/(?:index\.html|play\.html|game-loader\.js|site\.css|favicon\.ico)$/,
  /^\/game\/(?:manifest\.json|engine-config\.json|index(?:\.[A-Za-z0-9_-]+)*\.js)$/,
  /^\/chunks\/[A-Za-z0-9][A-Za-z0-9._-]*\.gz$/,
  /^\/images\/[A-Za-z0-9][A-Za-z0-9._-]*\.(?:png|jpe?g|webp|svg|ico)$/i,
  /^\/legal\/[A-Za-z0-9][A-Za-z0-9._-]*\.(?:html|txt|md)$/i,
];
class HostError extends Error {
  constructor(status, code) { super(code); this.status = status; }
}
function json(outgoing, status, body, headers = {}) {
  outgoing.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "x-sim2seoul-local-development": "1", ...headers });
  outgoing.end(JSON.stringify(body));
}
function pathname(target) {
  if (!target?.startsWith("/") || target.startsWith("//") || target.includes("#")) throw new HostError(400, "invalid_request_target");
  const raw = target.split("?", 1)[0];
  if (/%2f|%5c/i.test(raw)) throw new HostError(400, "invalid_asset_path");
  let decoded;
  try { decoded = decodeURIComponent(raw); } catch { throw new HostError(400, "invalid_asset_path"); }
  if (decoded.includes("\\") || decoded.includes("\0") || decoded.split("/").some(part => part === "." || part === "..")) throw new HostError(400, "invalid_asset_path");
  return decoded;
}
function bodyBytes(incoming) {
  if (Number(incoming.headers["content-length"]) > POLICY.maximumBodyBytes) {
    incoming.resume(); throw new HostError(413, "body_too_large");
  }
  return new Promise((accept, reject) => {
    const parts = []; let bytes = 0; let ended = false;
    incoming.on("data", part => {
      if (ended) return;
      bytes += part.length;
      if (bytes > POLICY.maximumBodyBytes) { ended = true; parts.length = 0; reject(new HostError(413, "body_too_large")); }
      else parts.push(part);
    });
    incoming.on("end", () => { if (!ended) { ended = true; accept(Buffer.concat(parts)); } });
    incoming.on("error", () => { if (!ended) { ended = true; reject(new HostError(400, "request_incomplete")); } });
    incoming.on("aborted", () => { if (!ended) { ended = true; reject(new HostError(400, "request_incomplete")); } });
  });
}

export async function startDevServer({ dist, apiOnly = false, port = 8766, now = () => Date.now() } = {}) {
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new TypeError("Invalid local port");
  let staticRoot = null;
  if (!apiOnly) {
    if (!dist) throw new TypeError("--dist is required unless --api-only is used");
    staticRoot = await realpath(resolve(dist));
    for (const required of ["play.html", "game/manifest.json"]) {
      const checked = await realpath(resolve(staticRoot, required));
      if (!checked.startsWith(staticRoot + sep) || !(await stat(checked)).isFile()) throw new TypeError("Invalid exported dist");
    }
  }
  const DB = createLocalD1();
  const api = createRoomApi({ now });
  const sessions = new Map();
  let origin, cookieName;
  function session(incoming) {
    const values = (incoming.headers.cookie ?? "").split(";").map(value => value.trim()).filter(value => value.startsWith(cookieName + "="));
    if (values.length > 1) throw new HostError(400, "ambiguous_dev_session");
    const token = values[0]?.slice(cookieName.length + 1);
    if (!token || !/^[a-f0-9]{64}$/.test(token)) return null;
    const value = sessions.get(token);
    if (!value || value.expiresAtMs <= now()) { sessions.delete(token); return null; }
    return { token, ...value };
  }
  const server = createServer(async (incoming, outgoing) => {
    try {
      const hostCount = incoming.rawHeaders.filter((_, index) => index % 2 === 0).filter(name => name.toLowerCase() === "host").length;
      if (hostCount !== 1 || incoming.headers.host !== new URL(origin).host || incoming.socket.remoteAddress !== "127.0.0.1") throw new HostError(403, "loopback_host_required");
      const path = pathname(incoming.url);
      const suppliedOrigin = incoming.headers.origin;
      if ((suppliedOrigin && suppliedOrigin !== origin) || (path.startsWith(PREFIX) && incoming.method === "POST" && !suppliedOrigin)) throw new HostError(403, "same_origin_required");
      if (path === PREFIX + "status") {
        if (incoming.method !== "GET") return json(outgoing, 405, { error: "method_not_allowed" }, { allow: "GET" });
        return json(outgoing, 200, { available: true, apiVersion: 1, mode: "local_development" });
      }
      if (path.startsWith(PREFIX)) {
        if (!["GET", "POST"].includes(incoming.method)) return json(outgoing, 405, { error: "method_not_allowed" }, { allow: "GET, POST" });
        let identity = session(incoming);
        if (path === PREFIX + "dev-session") {
          if (incoming.method !== "POST") return json(outgoing, 405, { error: "method_not_allowed" }, { allow: "POST" });
          if (incoming.headers["content-type"]?.split(";", 1)[0] !== "application/json") throw new HostError(415, "json_required");
          let value;
          try { value = JSON.parse((await bodyBytes(incoming)).toString("utf8")); } catch (error) { if (error instanceof HostError) throw error; throw new HostError(400, "invalid_json"); }
          if (!value || Array.isArray(value) || typeof value !== "object" || Object.keys(value).length) throw new HostError(400, "empty_object_required");
          if (!identity) {
            for (const [token, value] of sessions) if (value.expiresAtMs <= now()) sessions.delete(token);
            if (sessions.size >= DEV_SESSION.capacity) throw new HostError(429, "dev_session_capacity");
            identity = { token: randomBytes(32).toString("hex"), user: "local-development:" + randomUUID(), expiresAtMs: now() + DEV_SESSION.lifetimeMs };
            sessions.set(identity.token, { user: identity.user, expiresAtMs: identity.expiresAtMs });
          }
          // Browsers use this automatically. Native clients retain only name=value
          // from Set-Cookie in memory; no account ID or JS-readable auth token.
          return json(outgoing, 200, { developmentOnly: true, expiresAtMs: identity.expiresAtMs }, { "set-cookie": `${cookieName}=${identity.token}; HttpOnly; SameSite=Strict; Path=${PREFIX}; Max-Age=${Math.floor((identity.expiresAtMs - now()) / 1000)}` });
        }
        if (!identity) throw new HostError(401, "dev_session_required");
        const headers = new Headers(incoming.headers);
        for (const name of [...headers.keys()]) if (name.startsWith("oai-authenticated-")) headers.delete(name);
        headers.delete("cookie");
        headers.set("oai-authenticated-user-id", identity.user);
        const body = incoming.method === "POST" ? await bodyBytes(incoming) : undefined;
        const request = new Request(origin + incoming.url, { method: incoming.method, headers, ...(body === undefined ? {} : { body }) });
        const response = await api(request, { DB });
        outgoing.writeHead(response?.status ?? 404, { ...Object.fromEntries(response?.headers ?? []), "x-sim2seoul-local-development": "1" });
        return outgoing.end(response ? Buffer.from(await response.arrayBuffer()) : "");
      }
      if (!["GET", "HEAD"].includes(incoming.method)) return json(outgoing, 405, { error: "method_not_allowed" }, { allow: "GET, HEAD" });
      const requested = path === "/" ? "/index.html" : path === "/legal/" ? "/legal/index.html" : path;
      if (!staticRoot || !STATIC.some(pattern => pattern.test(requested))) throw new HostError(404, "asset_not_found");
      let file, details;
      try { file = await realpath(resolve(staticRoot, "." + requested)); details = await stat(file); } catch { throw new HostError(404, "asset_not_found"); }
      if (!file.startsWith(staticRoot + sep) || !details.isFile()) throw new HostError(404, "asset_not_found");
      outgoing.writeHead(200, { "content-type": MIME[extname(file).toLowerCase()] ?? "application/octet-stream", "content-length": details.size, "cache-control": "no-store", "x-content-type-options": "nosniff", "x-sim2seoul-local-development": "1" });
      if (incoming.method === "HEAD") return outgoing.end();
      createReadStream(file).on("error", () => outgoing.destroy()).pipe(outgoing);
    } catch (error) {
      incoming.resume();
      if (outgoing.headersSent || outgoing.destroyed) return outgoing.destroy();
      json(outgoing, error instanceof HostError ? error.status : 500, { error: error instanceof HostError ? error.message : "local_host_unavailable" });
    }
  });
  server.requestTimeout = 10_000; server.headersTimeout = 10_000;
  try { server.listen(port, "127.0.0.1"); await once(server, "listening"); }
  catch (error) { DB.close(); throw error; }
  origin = `http://127.0.0.1:${server.address().port}`;
  cookieName = `sim2seoul_dev_${server.address().port}`; // Cookies have no built-in port scope.
  let closed = false;
  return { origin, cookieName, server, DB, staticRoot, async close() {
    if (closed) return; closed = true;
    await new Promise((accept, reject) => server.close(error => error ? reject(error) : accept()));
    sessions.clear(); DB.close();
  } };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { dist: { type: "string" }, port: { type: "string", default: "8766" }, "api-only": { type: "boolean", default: false } } });
  const host = await startDevServer({ dist: values.dist, port: Number(values.port), apiOnly: values["api-only"] });
  console.log(JSON.stringify({ event: "SIM2SEOUL_DEV_HOST_READY", origin: host.origin, developmentOnly: true, sqlite: "memory", apiOnly: values["api-only"], staticRoot: host.staticRoot }));
  for (const signal of ["SIGINT", "SIGTERM"]) process.once(signal, async () => { await host.close(); process.exit(0); });
}
