# 0007 Shared lists are .dgsliste files

Status: accepted

## Context

Android `content:` URIs often omit file extensions, causing `.dgsliste` intent filters to fail.
`XFile.readAsString` defaults to latin-1 when given bytes instead of a path, mangling umlauts.

## Decision

Shared lists use JSON with a `.dgsliste` extension, containing both IDs and words.

The Android manifest includes both loose and strict intent filters. The file picker is the guaranteed fallback.

Files are read via `readText` in `lib/platform/files.dart` to enforce UTF-8 decoding. Malformed bytes fail gracefully in parsers.

## Consequences

Sharing works via messengers usually, with the file picker covering edge cases. iOS share menu requires an unbuilt share extension.
