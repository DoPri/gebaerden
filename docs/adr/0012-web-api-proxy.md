# 0012 The web build goes through a proxy

Status: accepted

## Context

`signdict.org` sends no `access-control-allow-origin` header. Browsers block cross-origin requests.

## Decision

A proxy sits between the web app and `signdict.org`. The proxy sets CORS headers and forwards the GraphQL queries and video requests. It runs as part of the containerized web deployment (see ADR 0015).

## Consequences

The web version requires backend proxying, meaning "No backend" applies only to the native apps. The proxy owner absorbs the API traffic and implements rate limiting. The proxy config duplicates the API endpoint.

Videos and thumbnails route through an `img` element (`webHtmlElementStrategy: fallback`) because `assets.wishlephant.com` also lacks CORS headers.
