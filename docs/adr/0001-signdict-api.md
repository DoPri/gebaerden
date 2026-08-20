# 0001 The dictionary comes from the SignDict API

Status: accepted

## Context

The app uses signdict.org for all signs and videos. Upstream corpus changes frequently.

## Decision

The GraphQL endpoint is the single source of truth. Metadata is cached locally; videos are downloaded on request. Network client limits concurrency to four requests with 60ms delays.

Integration tests verify API contracts. Unit tests run offline.

## Consequences

A network connection is required on first launch. Cached data remains available offline. Missing thumbnails return 403s and do not fail the parent package.
