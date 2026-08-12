# 0002 The full index instead of letter search

Status: accepted

## Context

`search(letter:)` folds Ä, Ö and Ü onto A and hands back the A list for all
three. Walked letter by letter it misses roughly 600 entries.

`index()` is the only complete view. Its `perPage` is capped at 100 by the
server, and it runs by id ascending, so its tail holds pages of search scanner
junk without video.

The trainer draws its candidates from the entry cache. Nothing used to fill
that cache, so a fresh install opened the learn tab on zero new and zero due.

## Decision

The corpus walk pages through `index()` and writes the result into the entry
cache. The completion marker is written last, so a walk that broke off halfway
is not remembered as complete.

The newest entries are read by walking back from the last page, skipping the
scanner junk until enough real signs turn up. The last reached page is stored
as a hint for the next run.

Letter search stays for browsing a single letter, where the umlaut folding is
visible and harmless.

## Consequences

A full walk costs a few hundred kilobytes. It fetches metadata, not footage,
so it is nowhere near the half gigabyte the videos would be.

The walk runs unwatched while the app boots and never throws. Offline is the
ordinary case and not worth a message.
