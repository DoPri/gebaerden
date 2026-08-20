# 0016 The tour sits above the router

Status: accepted

## Context

The first-start walkthrough highlights UI elements and navigates across tabs and pushed screens (e.g., video entries). Overlays inside the tab shell are hidden by pushed routes, and `GlobalKey` anchors fail on duplicate widgets.

## Decision

`Tour` wraps `MaterialApp.router` via its `builder`, sitting above the navigator. It commands `GoRouter` directly (using `go` for tabs, `push` for entries).

`TourAnchor` registers targets, prioritizing the most recently mounted. Cutouts are remeasured per-frame to track dynamic layouts.

## Consequences

The system back button ignores the tour overlay. It pops the current route or exits the app. The tour state is only marked complete on deliberate finish, so aborting restarts it later.
