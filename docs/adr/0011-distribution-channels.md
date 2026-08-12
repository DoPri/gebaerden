# 0011 Three distribution channels, three signatures

Status: accepted

## Context

The app should reach users who avoid Google and users who only ever install
from Play. Those are different distribution systems with incompatible
requirements.

F-Droid builds from source itself and signs with its own key. It rejects the
Google-signed dependency metadata an Android build embeds by default.

Play refuses APKs for new apps and takes only bundles. Play App Signing means
Google holds the app signing key and re-signs every upload, so the developer
key is reduced to an upload key.

Obtainium and a plain sideload need an installable APK per architecture.

Android identifies an app by package name plus signing certificate. Three
signers therefore mean three installs that cannot update each other.

## Decision

All three channels are served, driven by one tag.

The GitHub release carries split APKs signed with `release.jks`. Play gets an
AAB signed with the same key as the upload key. F-Droid builds from the tag on
its own infrastructure.

A tag with a suffix, `v1.0.1-rc1`, is a pre-release. It stays on GitHub and
never reaches Play, which is what makes testing possible without burning a
version in the store.

A tag without a suffix uploads to the Play internal testing track and stops
there. Promotion to production is a manual step in the console.

The store listing lives once, in `fastlane/metadata/android/`. F-Droid reads it
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
