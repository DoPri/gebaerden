import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final _plugin = FlutterLocalNotificationsPlugin();

/// The same check the plugin runs, anywhere else it has no implementation.
/// A browser on a phone reports android or iOS as well, and the plugins behind
/// this would answer with a missing implementation before the app is even up.
bool get _supported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

const weekdayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

const weekdayLongNames = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

/// Days are ISO, 1 is Monday.
@immutable
class Reminder {
  const Reminder({
    required this.days,
    required this.hour,
    required this.minute,
  });

  final Set<int> days;
  final int hour;
  final int minute;

  bool get daily => days.length == 7;

  String get time =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Reminder copyWith({Set<int>? days, int? hour, int? minute}) => Reminder(
    days: days ?? this.days,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
  );

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.hour == hour &&
      other.minute == minute &&
      other.days.length == days.length &&
      other.days.containsAll(days);

  @override
  int get hashCode => Object.hash(hour, minute, Object.hashAllUnordered(days));
}

/// hh:mm, the shape the time picker produces.
({int hour, int minute})? parseTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;

  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}

/// One entry per line, days and time separated by a space: `12345 08:00`.
String encodeReminders(List<Reminder> reminders) => [
  for (final r in reminders) '${(r.days.toList()..sort()).join()} ${r.time}',
].join('\n');

List<Reminder> parseReminders(String value) {
  final out = <Reminder>[];
  for (final line in value.split('\n')) {
    final parts = line.trim().split(' ');
    if (parts.length != 2) continue;

    final days = {
      for (final c in parts.first.split(''))
        if (int.tryParse(c) case final d? when d >= 1 && d <= 7) d,
    };
    final at = parseTime(parts.last);
    if (days.isEmpty || at == null) continue;

    out.add(Reminder(days: days, hour: at.hour, minute: at.minute));
  }
  return out;
}

/// Says when it fires, in the words the settings screen uses.
String describeReminder(Reminder reminder) {
  final days = reminder.days.toList()..sort();
  final when = switch (days) {
    _ when days.length == 7 => 'Täglich',
    [1, 2, 3, 4, 5] => 'Werktags',
    [6, 7] => 'Am Wochenende',
    [final one] => weekdayNames[one - 1],
    _ => days.map((d) => weekdayNames[d - 1]).join(', '),
  };
  return '$when um ${reminder.time} Uhr';
}

/// The count is baked in when scheduling, so it goes stale within a day.
String reminderBody(int due) =>
    due > 0 ? '$due Karten warten auf dich.' : 'Zeit für ein paar Gebärden.';

/// The first occurrence at or after now. Repetition is left to
/// matchDateTimeComponents.
tz.TZDateTime nextOccurrence(
  ({int hour, int minute}) at, {
  int? weekday,
  tz.TZDateTime? now,
}) {
  final from = now ?? tz.TZDateTime.now(tz.local);

  // Rebuilt from the calendar parts on every step. Adding a Duration moves the
  // instant by exactly 24 hours, which shifts the wall clock by an hour across
  // a daylight saving change.
  tz.TZDateTime on(int days) => tz.TZDateTime(
    from.location,
    from.year,
    from.month,
    from.day + days,
    at.hour,
    at.minute,
  );

  var day = on(0).isAfter(from) ? 0 : 1;
  // Seven steps cover every weekday. The bound keeps a day outside 1..7 from
  // spinning forever.
  final last = day + 7;
  while (weekday != null && day < last && on(day).weekday != weekday) {
    day++;
  }
  return on(day);
}

/// Reminders take the low ids, a download sits above. Both sides only ever
/// cancel their own, cancelAll would take the other one with it.
const _firstPackageId = 1000;

int _packageId(String group) => _firstPackageId + group.hashCode.abs() % 100000;

/// What a tap on a button in the download notification asks for.
typedef PackageAction = void Function(String action, String group);

/// Whoever owns the queue puts itself here. The response handler asks for it
/// when a button is pressed rather than taking it at startup: this used to be
/// an argument of [initNotifications], main stopped passing it, and nothing
/// said so. The buttons still drew, still woke the app, and dropped the press.
PackageAction? packageActionHandler;

Future<void> initNotifications() async {
  if (!_supported) return;
  tzdata.initializeTimeZones();
  final zone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(zone.identifier));

  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
    onDidReceiveNotificationResponse: _onResponse,
  );
}

/// A tap that started the app cold never reaches the callback above, it waits
/// here instead. Called once the app is up: during main() the plugin channel
/// does not answer, and reminderTapHandler is not set yet either.
Future<void> handleNotificationLaunch() async {
  if (!_supported) return;
  final launch = await _plugin.getNotificationAppLaunchDetails();
  final response = launch?.notificationResponse;
  if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
    _onResponse(response);
  }
}

/// Whoever owns the navigator puts itself here, the same way the queue does
/// for the buttons in the shade.
typedef ReminderTap = void Function(String listId);
ReminderTap? reminderTapHandler;

void _onResponse(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null) return;

  if (payload.startsWith(reminderPayload)) {
    reminderTapHandler?.call(payload.substring(reminderPayload.length));
    return;
  }
  final action = response.actionId;
  if (action != null) packageActionHandler?.call(action, payload);
}

/// Mirrors a package row into the shade: same label, same counts, same state
/// as the row on the offline screen. The downloader brings its own group
/// notification, but that one counts the tasks it has been handed so far, not
/// the ones the package plans, so its numbers jumped and it started over with
/// every block. This one reads the row.
Future<void> showPackage({
  required String group,
  required String label,
  required int done,
  required int total,
  required bool paused,
  String? note,
}) async {
  if (!_supported) return;

  await _plugin.show(
    id: _packageId(group),
    title: label,
    body: switch (null) {
      _ when note != null => note,
      _ when paused => 'Pausiert bei $done von $total',
      _ when total > 0 => '$done von $total',
      _ => 'Wird vorbereitet…',
    },
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'downloads',
        'Downloads',
        channelDescription: 'Fortschritt beim Herunterladen',
        importance: Importance.low,
        priority: Priority.low,
        // Silent on every update, otherwise it pings on every file.
        onlyAlertOnce: true,
        // Not swipeable while it runs, the download would keep going.
        ongoing: !paused,
        autoCancel: false,
        showProgress: total > 0,
        maxProgress: total,
        progress: done.clamp(0, total < 0 ? 0 : total),
        indeterminate: total == 0,
        // showsUserInterface brings the app up, and only then does the answer
        // reach it: a button pressed while the app sits in the background goes
        // to an isolate of its own that knows neither the database nor the
        // queue. cancelNotification off, the shade follows the row and the row
        // alone decides when the notification goes.
        actions: [
          AndroidNotificationAction(
            paused ? 'resume' : 'pause',
            paused ? 'Fortsetzen' : 'Pausieren',
            showsUserInterface: true,
            cancelNotification: false,
          ),
          const AndroidNotificationAction(
            'cancel',
            'Abbrechen',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(presentBanner: false),
    ),
    payload: group,
  );
}

Future<void> hidePackage(String group) async {
  if (!_supported) return;
  await _plugin.cancel(id: _packageId(group));
}

/// Everything the last run left in the shade. A row that is gone cannot say
/// so itself, and an ongoing notification outlives the process.
Future<void> hideAllPackages() async {
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return;

  for (final active in await android.getActiveNotifications()) {
    if ((active.id ?? 0) >= _firstPackageId) {
      await _plugin.cancel(id: active.id!);
    }
  }
}

Future<bool> _permitted({required bool ask}) async {
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android != null) {
    if (!ask) return await android.areNotificationsEnabled() ?? false;
    return await android.requestNotificationsPermission() ?? false;
  }

  final ios = _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
  if (ios != null && ask) {
    return await ios.requestPermissions(alert: true, sound: true) ?? false;
  }
  return true;
}

/// Only the reminders. cancelAll would take a running download's notification
/// with it, and that one has nothing to do with the alarms.
Future<void> cancelReminders() async {
  if (!_supported) return;
  for (final pending in await pendingReminders()) {
    await _plugin.cancel(id: pending.id);
  }
}

/// What is actually queued with the system. Used by the device tests.
Future<List<PendingNotificationRequest>> pendingReminders() async => _supported
    ? (await _plugin.pendingNotificationRequests())
          .where((p) => p.id < _firstPackageId)
          .toList()
    : [];

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'reminder',
    'Erinnerung',
    channelDescription: 'Erinnerung zum Üben',
  ),
  iOS: DarwinNotificationDetails(),
);

/// The list a reminder belongs to, so a tap lands in its trainer.
const reminderPayload = 'lernen:';

Future<void> _put(
  int id,
  ({int hour, int minute}) at,
  int? weekday,
  int due,
  String listId,
) => _plugin.zonedSchedule(
  id: id,
  title: 'Gebärden üben',
  body: reminderBody(due),
  payload: '$reminderPayload$listId',
  scheduledDate: nextOccurrence(at, weekday: weekday),
  notificationDetails: _details,
  // Exact alarms need a separate permission and this is not time critical.
  androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  matchDateTimeComponents: weekday == null
      ? DateTimeComponents.time
      : DateTimeComponents.dayOfWeekAndTime,
);

/// One entry per reminder: the reminder, the list it belongs to and how many
/// of that list's cards are waiting.
typedef DueReminder = ({Reminder reminder, String listId, int due});

Future<void> _schedule(List<DueReminder> reminders) async {
  await cancelReminders();

  var id = 1;
  for (final (:reminder, :listId, :due) in reminders) {
    final at = (hour: reminder.hour, minute: reminder.minute);
    if (reminder.daily) {
      await _put(id++, at, null, due, listId);
      continue;
    }
    for (final day in reminder.days.toList()..sort()) {
      await _put(id++, at, day, due, listId);
    }
  }
}

/// Asks for permission. False means the user said no.
Future<bool> scheduleReminders(List<DueReminder> reminders) async {
  if (!_supported) return false;
  if (!await _permitted(ask: true)) return false;
  await _schedule(reminders);
  return true;
}

/// Rewrites the count without prompting again.
Future<void> refreshReminders(List<DueReminder> reminders) async {
  if (!_supported || reminders.isEmpty) return;
  if (!await _permitted(ask: false)) return;
  await _schedule(reminders);
}
