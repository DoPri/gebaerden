# 0006 German collation and folding

Status: accepted

## Context

Dart string comparisons sort Ä, Ö, and Ü after Z. Alphabetical lists must reflect German sorting.

Search requires fuzzy matching where "bar" finds "Bär".

## Decision

Sorting uses `compareDe` in `lib/util/text.dart` (DIN 5007-1): umlauts sort with base letters, ß sorts as ss.

Search folds case, umlauts, and punctuation, ranking exact matches above prefixes. Offline search allows a bounded edit distance (one typo, two swapped letters).

## Consequences

Sorting and searching use distinct code paths to satisfy opposite requirements. The offline index scans ~5300 entries in memory, rebuilding after every cache write to stay current.
