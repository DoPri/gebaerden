import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/platform/notify.dart';

import 'channels.dart';

const _daily = Reminder(days: {1, 2, 3, 4, 5, 6, 7}, hour: 19, minute: 0);
const _weekdays = Reminder(days: {1, 2, 3, 4, 5}, hour: 8, minute: 0);

/// Tests platform notification channel interactions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChannels channels;

  setUp(() => channels = FakeChannels()..install());
  tearDown(() => channels.remove());

  test('setting up asks the device for its time zone', () async {
    await initNotifications();
    expect(channels.calls, contains('flutter_timezone.getLocalTimezone'));
    expect(
      channels.calls,
      contains('dexterous.com/flutter/local_notifications.initialize'),
    );
  });

  test('a daily reminder is one repeating alarm', () async {
    await initNotifications();
    expect(
      await scheduleReminders([(reminder: _daily, listId: 'kueche', due: 5)]),
      isTrue,
    );

    final call = channels.scheduled.single;
    expect(call['title'], 'Gebärden üben');
    expect(call['body'], '5 Karten warten auf dich.');
    expect(call['scheduledDateTime'], contains('19:00'));
    expect(call['matchDateTimeComponents'], DateTimeComponents.time.index);
  });

  test('picked days become one alarm each', () async {
    await initNotifications();
    await scheduleReminders([(reminder: _weekdays, listId: 'kueche', due: 0)]);

    expect(channels.scheduled, hasLength(5));
    for (final call in channels.scheduled) {
      expect(call['scheduledDateTime'], contains('08:00'));
      expect(
        call['matchDateTimeComponents'],
        DateTimeComponents.dayOfWeekAndTime.index,
      );
    }
  });

  test('several reminders are scheduled side by side', () async {
    await initNotifications();
    await scheduleReminders(const [
      (reminder: _weekdays, listId: 'kueche', due: 0),
      (
        reminder: Reminder(days: {6, 7}, hour: 11, minute: 30),
        listId: 'familie',
        due: 0,
      ),
    ]);

    expect(channels.scheduled, hasLength(7));
    final times = channels.scheduled
        .map((c) => '${c['scheduledDateTime']}')
        .toList();
    expect(times.where((t) => t.contains('08:00')), hasLength(5));
    expect(times.where((t) => t.contains('11:30')), hasLength(2));
  });

  test('the old ones go before the new ones', () async {
    await initNotifications();
    channels.pending = [
      {'id': 1, 'title': 'Gebärden üben', 'body': 'egal'},
    ];
    await scheduleReminders([(reminder: _daily, listId: 'kueche', due: 1)]);

    expect(
      channels.calls,
      containsAllInOrder([
        'dexterous.com/flutter/local_notifications.cancel',
        'dexterous.com/flutter/local_notifications.zonedSchedule',
      ]),
    );
  });

  test('without permission nothing is scheduled', () async {
    channels.notificationsAllowed = false;
    expect(
      await scheduleReminders([(reminder: _daily, listId: 'kueche', due: 1)]),
      isFalse,
    );
    expect(channels.scheduled, isEmpty);
  });

  test('an empty list only clears', () async {
    channels.pending = [
      {'id': 1, 'title': 'Gebärden üben', 'body': 'egal'},
    ];
    await scheduleReminders([]);

    expect(channels.scheduled, isEmpty);
    expect(
      channels.calls,
      contains('dexterous.com/flutter/local_notifications.cancel'),
    );
  });

  test('refreshing rewrites the count without asking again', () async {
    await refreshReminders([(reminder: _daily, listId: 'kueche', due: 3)]);

    expect(channels.scheduled.single['body'], '3 Karten warten auf dich.');
    expect(
      channels.calls,
      isNot(
        contains(
          'dexterous.com/flutter/local_notifications.'
          'requestNotificationsPermission',
        ),
      ),
    );
  });

  test('refreshing does nothing without a reminder', () async {
    await refreshReminders([]);
    expect(channels.scheduled, isEmpty);
  });

  test('refreshing does nothing when notifications are switched off', () async {
    channels.notificationsAllowed = false;
    await refreshReminders([(reminder: _daily, listId: 'kueche', due: 3)]);
    expect(channels.scheduled, isEmpty);
  });

  test('taking it back cancels the alarms and nothing else', () async {
    // IDs >= 1000 belong to downloads; cancelReminders must only clear reminder IDs.
    channels.pending = [
      {'id': 1, 'title': 'Gebärden üben', 'body': 'egal'},
      {'id': 2, 'title': 'Gebärden üben', 'body': 'egal'},
      {'id': 1234, 'title': 'Alle Gebärden', 'body': '5 von 99'},
    ];
    await cancelReminders();

    expect(channels.cancelled, [1, 2]);
    expect(
      channels.calls,
      isNot(contains('dexterous.com/flutter/local_notifications.cancelAll')),
    );
  });

  test('a tap on a reminder names the list it came from', () async {
    final opened = <String>[];
    reminderTapHandler = opened.add;
    addTearDown(() => reminderTapHandler = null);
    await initNotifications();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'dexterous.com/flutter/local_notifications',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('didReceiveNotificationResponse', {
              'notificationResponseType': 0,
              'id': 1,
              'payload': '${reminderPayload}kueche',
            }),
          ),
          (_) {},
        );

    expect(opened, ['kueche']);
  });

  test('a tap that started the app cold still reaches the trainer', () async {
    // Cold launch notification payload is retrieved via getNotificationAppLaunchDetails.
    channels.launchPayload = '${reminderPayload}kueche';
    final opened = <String>[];
    reminderTapHandler = opened.add;
    addTearDown(() => reminderTapHandler = null);
    await initNotifications();

    await handleNotificationLaunch();

    expect(opened, ['kueche']);
  });

  test('a start that no notification began opens nothing', () async {
    final opened = <String>[];
    reminderTapHandler = opened.add;
    addTearDown(() => reminderTapHandler = null);
    await initNotifications();

    await handleNotificationLaunch();

    expect(opened, isEmpty);
  });

  test('what is queued comes back', () async {
    channels.pending = [
      {
        'id': 1,
        'title': 'Gebärden üben',
        'body': 'Zeit für ein paar Gebärden.',
      },
    ];
    final pending = await pendingReminders();
    expect(pending.single.id, 1);
    expect(pending.single.body, 'Zeit für ein paar Gebärden.');
  });

  test('a platform without notifications queues nothing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    channels.pending = [
      {'id': 1, 'title': 'Gebärden üben', 'body': 'egal'},
    ];

    expect(await pendingReminders(), isEmpty);
    expect(
      await scheduleReminders([(reminder: _daily, listId: 'kueche', due: 1)]),
      isFalse,
    );
    expect(channels.scheduled, isEmpty);
  });
}
