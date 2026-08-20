import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/platform/notify.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
  });

  group('the download notification', () {
    late FakeChannels channels;

    setUp(() => channels = FakeChannels()..install());
    tearDown(() => channels.remove());

    test('a leftover from the last run is taken down', () async {
      channels.active = [
        {'id': 3, 'title': 'Gebärden üben'},
        {'id': 1234, 'title': 'Alle Gebärden'},
      ];

      await hideAllPackages();
      expect(channels.cancelled, [1234]);
    });

    test('a button reaches the app with the package it belongs to', () async {
      final asked = <String>[];
      packageActionHandler = (action, group) => asked.add('$action:$group');
      addTearDown(() => packageActionHandler = null);
      await initNotifications();

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'dexterous.com/flutter/local_notifications',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('didReceiveNotificationResponse', {
                'notificationResponseType': 1,
                'id': 1234,
                'actionId': 'pause',
                'payload': 'all',
              }),
            ),
            (_) {},
          );

      expect(asked, ['pause:all']);
    });

    test('a paused package says so, a running one counts', () async {
      await showPackage(
        group: 'all',
        label: 'Alle Gebärden',
        done: 5,
        total: 99,
        paused: false,
      );
      expect(channels.shown.last['body'], '5 von 99');

      await showPackage(
        group: 'all',
        label: 'Alle Gebärden',
        done: 5,
        total: 99,
        paused: true,
      );
      expect(channels.shown.last['body'], contains('Pausiert'));

      await showPackage(
        group: 'all',
        label: 'Alle Gebärden',
        done: 0,
        total: 0,
        paused: false,
      );
      expect(channels.shown.last['body'], contains('vorbereitet'));
    });
  });

  group('parsing the time', () {
    test('takes what the picker produces', () {
      expect(parseTime('07:30'), (hour: 7, minute: 30));
      expect(parseTime('7:05'), (hour: 7, minute: 5));
      expect(parseTime('  19:00  '), (hour: 19, minute: 0));
    });

    test('rejects nonsense', () {
      expect(parseTime('25:00'), isNull);
      expect(parseTime('07:99'), isNull);
      expect(parseTime('halb acht'), isNull);
      expect(parseTime(''), isNull);
      expect(parseTime('730'), isNull);
    });
  });

  group('the text', () {
    test('names the count when something is due', () {
      expect(reminderBody(12), contains('12'));
    });

    test('drops the number when nothing is due', () {
      expect(reminderBody(0), isNot(matches(RegExp(r'\d'))));
    });
  });

  group('the next occurrence', () {
    test('is today when the time is still ahead', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 7, 9);
      final next = nextOccurrence((hour: 19, minute: 0), now: now);
      expect(next.day, 7);
      expect(next.hour, 19);
    });

    test('is tomorrow when the time has passed', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 7, 20);
      final next = nextOccurrence((hour: 19, minute: 0), now: now);
      expect(next.day, 8);
      expect(next.hour, 19);
    });

    test('exactly now still means tomorrow', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 7, 19);
      expect(nextOccurrence((hour: 19, minute: 0), now: now).day, 8);
    });

    test('rolls over the month', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 31, 23);
      final next = nextOccurrence((hour: 8, minute: 0), now: now);
      expect(next.month, 9);
      expect(next.day, 1);
    });

    test('keeps the hour across the spring change', () {
      // DST transition in Berlin.
      final now = tz.TZDateTime(tz.local, 2026, 3, 28, 10);
      final next = nextOccurrence((hour: 8, minute: 0), now: now);
      expect(next.day, 29);
      expect(next.hour, 8);
    });

    test('keeps the hour across the autumn change', () {
      // DST return to standard time.
      final now = tz.TZDateTime(tz.local, 2026, 10, 24, 10);
      final next = nextOccurrence((hour: 8, minute: 0), now: now);
      expect(next.day, 25);
      expect(next.hour, 8);
    });
  });

  group('a reminder', () {
    test('survives the round trip through the setting', () {
      const list = [
        Reminder(days: {1, 2, 3, 4, 5}, hour: 8, minute: 0),
        Reminder(days: {6, 7}, hour: 11, minute: 30),
      ];
      expect(parseReminders(encodeReminders(list)), list);
    });

    test('a broken line is dropped, the rest stays', () {
      final parsed = parseReminders('12345 08:00\nunsinn\n9 25:00\n67 11:30');
      expect(parsed, hasLength(2));
      expect(parsed.last.days, {6, 7});
    });

    test('nothing stored means no reminder', () {
      expect(parseReminders(''), isEmpty);
    });

    test('says in words when it fires', () {
      expect(
        describeReminder(
          const Reminder(days: {1, 2, 3, 4, 5, 6, 7}, hour: 19, minute: 0),
        ),
        'Täglich um 19:00 Uhr',
      );
      expect(
        describeReminder(
          const Reminder(days: {1, 2, 3, 4, 5}, hour: 8, minute: 0),
        ),
        'Werktags um 08:00 Uhr',
      );
      expect(
        describeReminder(const Reminder(days: {6, 7}, hour: 11, minute: 0)),
        'Am Wochenende um 11:00 Uhr',
      );
      expect(
        describeReminder(const Reminder(days: {3}, hour: 7, minute: 5)),
        'Mi um 07:05 Uhr',
      );
      expect(
        describeReminder(const Reminder(days: {1, 4}, hour: 7, minute: 5)),
        'Mo, Do um 07:05 Uhr',
      );
    });

    test('two that differ only in order are the same', () {
      expect(
        const Reminder(days: {7, 6}, hour: 9, minute: 0),
        const Reminder(days: {6, 7}, hour: 9, minute: 0),
      );
      expect(
        const Reminder(days: {6, 7}, hour: 9, minute: 0).hashCode,
        const Reminder(days: {7, 6}, hour: 9, minute: 0).hashCode,
      );
    });
  });

  group('the next occurrence on a weekday', () {
    test('is the coming one when it is still ahead', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 7, 9);
      final next = nextOccurrence((hour: 19, minute: 0), weekday: 6, now: now);
      expect(next.weekday, DateTime.saturday);
      expect(next.day, 8);
    });

    test('skips to next week when today has passed', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 7, 20);
      final next = nextOccurrence((hour: 19, minute: 0), weekday: 5, now: now);
      expect(next.weekday, DateTime.friday);
      expect(next.day, 14);
    });

    test('a day nobody has still comes to an end', () {
      // Bounds search to prevent infinite loop on invalid weekdays.
      final now = tz.TZDateTime(tz.local, 2026, 8, 7, 9);
      final next = nextOccurrence((hour: 8, minute: 0), weekday: 9, now: now);
      expect(next.isAfter(now), isTrue);
    });

    test('keeps the hour when the search crosses the clock change', () {
      // Crosses spring DST transition.
      final now = tz.TZDateTime(tz.local, 2026, 3, 28, 10);
      final next = nextOccurrence((hour: 8, minute: 0), weekday: 1, now: now);
      expect(next.weekday, DateTime.monday);
      expect(next.day, 30);
      expect(next.hour, 8);
    });
  });
}
