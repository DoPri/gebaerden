# 0010 The accent color is free and forced to contrast

Status: accepted

## Context

The accent color is picked by the user and the picker accepts anything. A
light yellow on the light scheme or a dark blue on the dark one would be
unreadable, and refusing colors in the picker would be the wrong answer to
that.

## Decision

A single ARGB value is stored. `accented` in `lib/theme.dart` walks the
lightness of whatever was picked until it clears 4.5:1 against the current
background, in both brightnesses.

## Consequences

The color on screen is not always exactly the one picked. Readability wins.

`test/a11y_test.dart` checks contrast in both brightnesses, for the suggested
accents and for the extremes like white, black and yellow.
