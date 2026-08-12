# 0008 Reminders are one alarm per weekday

Status: accepted

## Context

`flutter_local_notifications` stopped shipping its broadcast receivers in
version 16. Without two manifest entries the alarm is registered, nothing
fails, and the reminder never arrives. The daily reminder was reported as
finished while it had not fired once.

Android schedules repeats through `matchDateTimeComponents`, which knows
`time` and `dayOfWeekAndTime` and nothing in between. There is no "Monday,
Wednesday and Friday" alarm.

## Decision

The manifest pins `ScheduledNotificationReceiver` and
`ScheduledNotificationBootReceiver`, and `test/manifest_test.dart` holds both
so a plugin upgrade cannot drop them silently.

Picked weekdays become one alarm each with `dayOfWeekAndTime`. All seven days
collapse to a single alarm with `time`.

One line is stored per reminder, days and time separated by a space, for
example `12345 08:00`.

Reminders take the low notification ids and downloads sit above them. Neither
side calls `cancelAll`, which would take the other one down.

Alarms are inexact. An exact alarm needs a separate permission and a vocabulary
reminder is not time critical.

## Consequences

That an alarm is registered says nothing about whether the notification
arrives. The manifest test is the only automated guard, the rest has to be seen
on a device.

The due count is baked into the text when scheduling, so it goes stale within a
day. Opening the app rewrites it without prompting again.
