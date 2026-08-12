# 0006 German collation and folding

Status: accepted

## Context

Dart compares strings by codepoint. That puts Baum before Bär and sorts every
umlaut behind Z. The dictionary is German, so an alphabetical list ordered that
way is wrong on screen.

Search has the opposite need. Someone typing "bar" should still find "Bär", and
someone typing "Arbiet" should still find "Arbeit".

## Decision

Ordering goes through `compareDe` in `lib/util/text.dart`, which follows DIN
5007-1: umlauts file under their base letter, ß counts as ss.

Search folds case, umlaut spelling and punctuation, then ranks exact match
before prefix before the rest. Offline search adds a bounded edit distance that
forgives one typo and two swapped letters.

## Consequences

Bar and Bär fold together in search and stay apart in sorting. Both behaviours
are wanted and they do not share a code path.

The offline index is a scan over about 5300 entries in memory, which beats
holding a separate index. It is rebuilt after every write to the cache, since a
row count would miss a word rewritten under a standing id.
