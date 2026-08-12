# 0004 Entries without video stay out of the trainer

Status: accepted

## Context

Roughly 38 percent of the corpus carries no footage. A sign language card
without a clip has nothing to ask and nothing to answer.

## Decision

The deck is built only from entries with a playable video. The dictionary hides
them too by default, with a setting that shows them.

## Consequences

The counts in the learn tab are well below the corpus size, which is correct
rather than a bug to chase.

An entry that gains a video upstream enters the deck on the next cache write.
