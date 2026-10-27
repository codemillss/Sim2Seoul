# Shared-city Site source migration

`overlay/` contains only 11 authored differences from the official Sites Vinext
starter. `overlay.json` freezes their hashes and the official versions they
modify. The latest status route retains `signInRequired` derived solely from
the dispatch-owned visitor header. The authoritative room implementation is
always copied from `tools/web/multiplayer/room-api.mjs`, not stored in this overlay.

Run from the Sim2Seoul repository with an existing clean **static Site** checkout:

```sh
python3 tools/prepare_shared_city_site.py \
  --site /absolute/existing-site-checkout \
  --game-export /absolute/new-game-export/dist \
  --starter /absolute/sites-plugin/skills/sites/templates/vinext-starter \
  --report /absolute/fresh-preparation-report.json
```

The helper preserves the existing `project_id`, unrelated hosting fields, any
existing R2 binding, README and unrelated root files. It removes `static`, adds
`d1: "DB"` when absent/null, and adds `r2: null` only when absent. An existing
different D1 binding, app/database/public directory, dirty checkout, source
collision, symlink, or untracked/ignored old output file causes a preflight failure.
It never overwrites an existing Worker application.

All new starter/overlay/API/public files are hashed before old tracked generated
output is removed. The report records the previous commit and old output blobs;
they remain recoverable through Git. Only the recorded generated static output
is removed. No `.git`, dependencies, runtime state, credentials, or source secrets
are copied. The helper never installs, builds, applies migrations, commits, pushes,
calls native Site tools, changes audience, or publishes.

After reviewing the prepared source, use the official Sites helpers from that
checkout: `configure-execution-profile.mjs`, `install-dependencies.mjs`, and
`build-site.mjs`. The generated Drizzle SQL/journal/snapshot are source artifacts;
local and hosted migration application remain separate explicit workflow steps.
Retain the `sites()` and Cloudflare build integrations in `vite.config.ts`.

The dev-only `rawGameChunks` plugin prevents Vite from treating the game's gzip
payloads as HTTP compression. Production assets use `html_handling: "none"`,
preserving `/index.html`, `/play.html`, `/game/*` and `/chunks/*` URLs. `/play`
redirects to `/play.html` while preserving its query. `/` redirects to `/index.html`.

Fixture validation is available with:

```sh
python3 tools/web/site-worker/test_prepare.py \
  --game-export /absolute/verified-game-export/dist \
  --starter /absolute/sites-plugin/skills/sites/templates/vinext-starter \
  --report /absolute/fresh-fixture-report.json
```
