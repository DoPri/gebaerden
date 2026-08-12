# 0007 Shared lists are .dgsliste files

Status: accepted

## Context

Lists should travel between devices without an account or a server. Two
platform details get in the way.

Android rarely carries the file extension in the path of a `content:` URI, so
an intent filter matching on `.dgsliste` does not always fire.

`XFile.readAsString` ignores the encoding and falls back to latin-1 when the
picker hands over bytes instead of a path, which is what Android always does.
Umlauts arrive mangled.

## Decision

A list travels as a JSON file with the extension `.dgsliste`, carrying id and
word per entry so the receiver sees the contents before any network round trip.

The manifest keeps both a loose and a strict intent filter, and the file picker
under Listen is documented as the path that always works.

Picked files go through `readText` in `lib/platform/files.dart`, which decodes
UTF-8 itself. Malformed bytes become replacement characters and fail later in
the parsers with their German message.

## Consequences

Receiving through a messenger works most of the time and the picker covers the
rest.

iOS opens a shared list through the file picker and through "Öffnen mit". The
share menu needs a share extension, which is not built yet.
