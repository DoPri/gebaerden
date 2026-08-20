# 0015 The container serves the app and the API on one origin

Status: accepted

## Context

The web build consists of static files and the API proxy (ADR 0012). Browsers require both on the same origin to avoid CORS checks.

## Decision

A single nginx image serves `build/web` and proxies `/api` to signdict.org.

The image runs unprivileged on port 8080. TLS is delegated to an external reverse proxy. Client IPs for rate limiting are read from `X-Forwarded-For`.

The build verifies the Flutter SDK tarball by checksum and compiles on the build platform. `API_UPSTREAM` controls the API target via `/etc/resolv.conf`, avoiding rebuilds on endpoint changes.

## Consequences

Operators absorb the built-in rate limit and proxy behavior. The image runs read-only; nginx requires tmpfs mounts for its cache directories.

The image tag matches the APK tag. The web version lacks offline downloads (ADR 0013). Proxy configuration is validated manually in browser, not via automated integration tests.
