# 0005 Spaced repetition through dart-fsrs

Status: accepted

## Context

The scheduler uses FSRS. The `dart-fsrs` port differs from the `ts-fsrs` package used in the earlier web version (different weights, no explicit New state, no rollback). Dereferencing stability on post-learning cards can crash the trainer.

## Decision

`dart-fsrs` is used directly. Cards without stability count as unlearned (simulating a New state). Undo replays the snapshot from the review row.

Card IDs format as `entryId:direction` to separate learning directions.

## Consequences

Backups from the legacy Svelte version cannot be imported.

Suspension after eight lapses and daily limits are tracked locally via the review log, bypassing `dart-fsrs` for these features.
