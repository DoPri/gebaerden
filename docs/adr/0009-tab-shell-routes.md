# 0009 Tab shell routes are reached with go

Status: accepted

## Context

`/`, `/lernen`, `/listen` and `/mehr` live inside the tab shell. Pushing one of
them lays the shell on top of itself and aborts with a duplicate navigator key.

Every screen rendered correctly while "Diese Liste lernen" crashed the app,
because the button pushed instead of going.

## Decision

Navigation into a tab shell route uses `context.go`. Routes outside the shell,
such as an entry or a letter, are pushed as usual.

## Consequences

The way between screens is tested, not only the screens. A route transition
that only exists in a button callback is where this class of bug hides.
