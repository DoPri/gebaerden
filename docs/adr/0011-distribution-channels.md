# 0011 Four distribution channels

Status: accepted

## Context

Users obtain the app from Google Play, GitHub releases, F-Droid, or as a web app. Updates must reach all channels.

## Decision

out of the repository, Fastlane's `supply` pushes the same tree to Play.

`dependenciesInfo` stays off. F-Droid needs that, Play only loses the
dependency advisories in the console.

## Consequences

A user cannot switch between GitHub, Play and F-Droid without uninstalling
first, which deletes progress, lists and downloaded videos. The release notes
have to say so.

The versionCode has to rise on every release, because Play refuses one it has
already seen. F-Droid builds the same tag, so the code cannot be derived from
a CI run number.

Ruby enters the repository for `supply` and nothing else. It is not needed to
build, run or test the app.

A Play release can be halted but not withdrawn. That is why a tag stops at
internal testing rather than going out to everyone.
