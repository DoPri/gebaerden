# 0010 The accent color is free and forced to contrast

Status: accepted

## Context

Users can pick any accent color, which risks unreadable contrast (e.g., dark blue on a dark theme).

## Decision

Store the raw ARGB value. `accented` in `lib/theme.dart` adjusts lightness to guarantee a 4.5:1 contrast ratio against the current background.

## Consequences

Rendered colors may shift from the exact picked color to ensure readability. `test/a11y_test.dart` verifies contrast across brightness extremes.
