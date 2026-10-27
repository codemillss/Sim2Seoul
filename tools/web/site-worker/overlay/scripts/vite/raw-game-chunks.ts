import type { Plugin } from "vite";

/** These .gz files are verified application payloads, not HTTP compression.
 * Vite's dev static handler otherwise labels them Content-Encoding:gzip,
 * causing fetch to decompress before the game loader can verify the bytes.
 * Production Worker assets already preserve their original bytes/headers.
 */
export function rawGameChunks(): Plugin {
  return {
    name: "sim2seoul-raw-game-chunks",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        const path = (request.url ?? "").split("?", 1)[0];
        if (/^\/chunks\/[A-Za-z0-9][A-Za-z0-9._-]*\.gz$/.test(path)) {
          const setHeader = response.setHeader.bind(response);
          response.setHeader = (name, value) => {
            if (name.toLowerCase() === "content-encoding") return response;
            return setHeader(name, name.toLowerCase() === "content-type" ? "application/gzip" : value);
          };
        }
        next();
      });
    },
  };
}
