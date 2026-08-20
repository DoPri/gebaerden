# 0016 The tour sits above the router

Status: accepted

## Context

The walkthrough for a first start points at real widgets and walks the app
while it does. It switches tabs, and one step opens an entry so the video and
its controls are the thing being explained.

An overlay built inside the tab shell sits under every pushed route, so the
entry screen would cover it. Anchors by `GlobalKey` break as soon as a widget
exists twice, which two stacked entry screens do, they carry the same controls.

## Decision

`Tour` lives in the `builder` of `MaterialApp.router`, above the navigator, and
navigates through the `GoRouter` it is handed. Tab routes are reached with `go`,
the entry with `push`, and the next `go` drops it again.

Anchors register themselves through `TourAnchor`, the one mounted last wins.
The cutout is measured again after every frame, since a section that loads late
moves the widget under it.

## Consequences

The system back button does not reach the tour, there is no route to pop. It
pops the entry screen during the video step, and on a tab screen it leaves the
app with the marker unset, so the next start offers the tour again.
