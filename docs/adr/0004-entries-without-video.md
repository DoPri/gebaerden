# 0004 Entries without video stay out of the trainer

Status: accepted

## Context

Roughly 38 percent of the corpus lacks video footage.

## Decision

The trainer deck includes only entries with playable videos. The dictionary hides videoless entries by default.

## Consequences

Learn tab counts accurately reflect the playable subset of the corpus. Entries gaining video upstream are automatically added to the deck during the next cache write.
