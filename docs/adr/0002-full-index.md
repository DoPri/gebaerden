# 0002 The full index instead of letter search

Status: accepted

## Context

`search(letter:)` folds Ä, Ö, and Ü onto A, missing roughly 600 entries. `index()` provides the only complete view, capping at 100 per page ascending by ID.

## Decision

The corpus walk pages through `index()` to populate the entry cache. The completion marker is written last to prevent partial walks from registering as complete.

The newest entries are found by walking backward from the last page, skipping scanner junk. Letter search remains only for browsing single letters.

## Consequences

Full walks require minimal data transfer (metadata only). The walk runs in the background on startup without UI interruption.
