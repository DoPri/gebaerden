# 0009 Tab shell routes are reached with go

Status: accepted

## Context

Pushing tab routes (`/`, `/lernen`, `/listen`, `/mehr`) duplicates the shell and crashes with duplicate navigator keys.

## Decision

Navigation into shell routes uses `context.go`. External routes (entries, letters) use `push`.

## Consequences

UI tests must drive navigation flows, not just individual screens, to catch routing bugs.
