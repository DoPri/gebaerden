# 0008 Reminders are one alarm per weekday

Status: accepted

## Context

`flutter_local_notifications` v16+ requires explicit broadcast receivers in the manifest to fire alarms. Android scheduling (`matchDateTimeComponents`) only supports daily or single-weekday repeats.

## Decision

The manifest explicitly declares `ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver`, guarded by `test/manifest_test.dart`.

Specific weekdays become individual `dayOfWeekAndTime` alarms. All-week reminders use a single `time` alarm. Reminder configuration is stored as `12345 08:00`.

Reminders use low notification IDs; downloads use high IDs. Neither calls `cancelAll`. Alarms are inexact to avoid permission requirements.

## Consequences

Manifest tests guard against silent registration failures. The baked-in due count goes stale daily, refreshing when the app opens.
