# 0003 GraphQL errors are not retried

Status: accepted

## Context

The endpoint returns GraphQL errors with HTTP 200 and an `errors` array. Transport-level retries cannot distinguish this from success based on status codes.

## Decision

A 200 response containing `errors` raises `GraphqlError`, which never retries. Transport failures and 5xx raise `ApiError` and retry three times with exponential backoff and jitter. Lookups for missing IDs return null.

## Consequences

Malformed queries fail immediately. Callers handle missing data vs unreachable servers appropriately.
