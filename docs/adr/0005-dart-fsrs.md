# 0005 Spaced repetition through dart-fsrs

Status: accepted

## Context

The scheduler is FSRS, the algorithm Anki uses. The Dart port differs from the
`ts-fsrs` package the earlier Svelte version ran on. Its weights are not the
same, it has no New state, and it offers no rollback. It also dereferences
stability once a card is past learning, so a corrupted row can take the trainer
down.

## Decision

`dart-fsrs` is used as it is. A card without stability counts as unlearned,
which stands in for the missing New state. Undo replays the snapshot the review
row carries, since there is nothing to roll back to otherwise.

Card ids are `entryId:direction`, so the two directions of one word stay apart
and a merge can compare them.

Because the weights differ, backups from the Svelte version do not import.

## Consequences

Settled, not reopened. A user coming from the web version starts over.

Suspension at eight lapses and the daily limits are ours, `dart-fsrs` does not
track them. The review log is the counter, there is no extra bookkeeping.
