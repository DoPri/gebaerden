# 0003 GraphQL errors are not retried

Status: accepted

## Context

The endpoint answers GraphQL errors with HTTP 200 and an `errors` array in the
body. A transport-level retry cannot tell the two apart from the status code
alone.

## Decision

A 200 body carrying `errors` raises `GraphqlError`, which is deterministic and
never retried. Only transport failures and 5xx raise `ApiError` and are tried
again, three attempts with exponential backoff and jitter.

A lookup that reports "not found" is an answer, not a failure. A deleted or
mistyped id comes back as null.

## Consequences

A malformed query fails once instead of three times against a volunteer server.

Callers distinguish "the server said no" from "the server was unreachable",
which is what decides whether a screen shows the cache or an error line.
