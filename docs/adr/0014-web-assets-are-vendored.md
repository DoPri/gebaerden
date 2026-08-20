# 0014 The web build ships what it loads

Status: accepted

## Context

Flutter web builds fetch dependencies (CanvasKit, Roboto, Noto) from Google at runtime. Drift requires version-matched `sqlite3.wasm` and `drift_worker.js`. Remote loading fails on locked networks and causes version skew.

## Decision

All runtime dependencies are served from the app's own origin.

`flutter build web --no-web-resources-cdn` localizes CanvasKit. `tools/web_assets.py` extracts the drift worker, `sqlite3.wasm`, and localizes font paths, setting `fontFallbackBaseUrl` to `fonts/` in `web/flutter_bootstrap.js`.

The container enforces `Content-Security-Policy: default-src 'self'` to block external requests.

## Consequences

Flutter updates that move font paths will break the script loudly, requiring a rebuild rather than failing silently.

Using `flutter build web` without the script loads resources from Google. Only the scripted build path is supported.

`require-corp` is omitted from `Cross-Origin-Embedder-Policy` because the CDN lacks `cross-origin-resource-policy` headers, causing Drift to fall back to IndexedDB.
