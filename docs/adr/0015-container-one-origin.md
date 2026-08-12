# 0015 The container serves the app and the API on one origin

Status: accepted

## Context

The web build is static files plus the proxy from
[0012](0012-web-api-proxy.md). Those are two things to deploy, and the browser
only stops asking about CORS when they answer on the same origin.

A separate proxy host would mean CORS headers on that host, a second name, a
second certificate and a second thing to keep running. GitHub Pages cannot
proxy at all.

## Decision

One image. nginx serves `build/web` and forwards `location = /api` to
signdict.org, so the app calls its own address and no CORS header is needed
anywhere.

It listens on 8080 as uid 101 on `nginxinc/nginx-unprivileged` and speaks
plain HTTP. TLS belongs to the reverse proxy in front, which is also where the
client address comes from, read out of `X-Forwarded-For` for the rate limit.
`/healthz` answers for a health check.

The compiler stage is pinned to the Flutter version that
`.github/actions/setup/action.yml` names and verifies the SDK tarball by
checksum. It runs on the build platform, so adding a second architecture later
does not put the compile on an emulated runner.

`API_UPSTREAM` moves the upstream without a rebuild. The address is resolved
per request through the resolver the entrypoint reads out of `/etc/resolv.conf`,
so a changed address needs no restart and a DNS that is not up yet does not
keep nginx from starting.

A tag publishes the image to ghcr with the same build provenance attestation
the APKs carry, which extends [0011](0011-distribution-channels.md) by a
fourth channel. `docker-compose.yml` names that image and keeps a build
section, so a machine without it builds rather than failing.

## Consequences

Whoever runs the container runs the proxy, whether they wanted to or not. The
rate limit and the timeouts are therefore part of the image and not left to
the operator.

Nothing in the image writes, so it runs read only. The entrypoint renders its
configuration and nginx wants a cache directory, which needs two writable
tmpfs mounts, and the README carries the exact invocation.

The image and the APKs come out of the same tag and the same commit, so a
report about "the app" needs to say which one. The web version is missing the
downloads from [0013](0013-downloads-are-native.md).

Nothing here is tested on a device or against a real reverse proxy. What was
observed is the container itself, in a browser, against the live API.
