# 0013 Offline downloads are native only

Status: accepted

## Context

The offline feature relies on `background_downloader`, which lacks web support and imports `dart:io`. A web implementation would require Chromium-only Background Fetch APIs and route gigabytes of video through the proxy, contradicting cross-platform rules and burdening the proxy host.

## Decision

`lib/packages/manager.dart` uses conditional exports. `manager_io.dart` handles the native queue; `manager_web.dart` provides no-op stubs.

The `downloadsAvailable` flag gates offline UI sections so the browser offers only what it supports. `lib/platform/local.dart` uses the same pattern for file operations.

## Consequences

API changes to the downloader require updating both `manager_io.dart` and the `manager_web.dart` stubs to prevent compile failures.

The web version functions as an online-only dictionary. Widget tests load the `io` side, so `manager_web.dart` coverage is verified only by the web build itself.
