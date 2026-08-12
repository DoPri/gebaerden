# 0013 Offline downloads are native only

Status: accepted

## Context

The offline feature hands thousands of files to `background_downloader`, which
keeps working while the app is closed and reports through the notification
shade. `AGENTS.md` records what that cost to get right.

The package declares android, ios, linux, macos and windows, and no web. It
also imports `dart:io` in `base_downloader.dart`, so anything that reaches
`lib/packages/manager.dart` fails to compile for the browser rather than
failing at runtime. `manager.dart` is reached from the shell, the entry screen,
the list picker and the offline screen.

A browser could cache videos through Cache Storage or OPFS. Continuing while
the tab is closed needs the Background Fetch API, which is Chromium only, so a
web downloader would work in Chrome and nowhere else. That contradicts the
rule that a fix has to hold on every platform. The bytes would also have to
come through the proxy from [0012](0012-web-api-proxy.md), since
assets.wishlephant.com sends no CORS header, which turns roughly 450 MB per
user into somebody's bandwidth bill.

## Decision

`lib/packages/manager.dart` is a conditional export. `manager_io.dart` is the
queue as it was, `manager_web.dart` answers the same calls and does nothing.
The package descriptions both sides need live in `spec.dart`.

`downloadsAvailable` comes out of the same pair. The offline section under
Mehr, the button on an entry and the `/offline` route hang on it, so the
browser offers nothing it cannot deliver.

The same shape carries `dart:io` in general. `lib/platform/local.dart` exports
either `local_io.dart` or `local_web.dart` for the handful of places that read
a file, show one or write one for the share sheet.

## Consequences

Two files describe one class. A method added to the queue has to be added to
the empty side as well, or the web build stops compiling, which is the loud
failure and the reason this is a facade rather than a pile of `kIsWeb`.

The web version needs a connection for every video. It is a dictionary in a
browser tab, not an offline app.

Tests run on the VM and load the io side, so `manager_web.dart` is never
executed by them. It contributes nothing to coverage and nothing checks that
its signatures still line up except the web build itself, which CI runs.
