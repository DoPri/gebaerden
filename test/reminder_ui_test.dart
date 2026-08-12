import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/reminders.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/platform/notify.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/ui/widgets/reminder_panel.dart';

import 'channels.dart';
import 'harness.dart';
import 'support.dart';

/// The reminders of a list. They used to sit under Mehr and be global, so the
/// panel now needs a list to belong to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late StoredList list;

  setUp(() async {
    db = testDb();
    channels = FakeChannels()..install();
    // main() does this before any screen is up.
    await initNotifications();
    list = await createList(db, 'Küche');
  });

  tearDown(() async {
    channels.remove();
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      await harness(db, ReminderPanel(db: db, listId: list.id)),
    );
    await tester.pumpAndSettle();
  }

  Future<List<Reminder>> stored() async =>
      (await remindersFor(db, list.id)).map((s) => s.reminder).toList();

  Future<void> seed(Reminder reminder) => addReminder(db, list.id, reminder);

  testWidgets('a new one starts daily at the picked time', (tester) async {
    await open(tester);

    await tester.tap(find.text('Erinnerung einrichten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final reminders = await stored();
    expect(reminders.single.time, '19:00');
    expect(reminders.single.daily, isTrue);
    expect(channels.scheduled, hasLength(1));
    await drain(tester);
  });

  testWidgets('backing out of the picker changes nothing', (tester) async {
    await open(tester);

    await tester.tap(find.text('Erinnerung einrichten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(await stored(), isEmpty);
    expect(channels.scheduled, isEmpty);
    await drain(tester);
  });

  testWidgets('a day can be switched off and back on', (tester) async {
    await seed(
      const Reminder(days: {1, 2, 3, 4, 5, 6, 7}, hour: 7, minute: 30),
    );
    await open(tester);

    await tester.tap(find.bySemanticsLabel('Samstag'));
    await tester.pumpAndSettle();

    expect((await stored()).single.days, {1, 2, 3, 4, 5, 7});
    // Six days means six alarms, one for each.
    expect(channels.scheduled, hasLength(6));
    await drain(tester);
  });

  testWidgets('the last day cannot be switched off', (tester) async {
    await seed(const Reminder(days: {3}, hour: 7, minute: 30));
    await open(tester);

    await tester.tap(find.bySemanticsLabel('Mittwoch'));
    await tester.pumpAndSettle();

    expect((await stored()).single.days, {3});
    await drain(tester);
  });

  testWidgets('the time picker opens on the stored time', (tester) async {
    await seed(
      const Reminder(days: {1, 2, 3, 4, 5, 6, 7}, hour: 7, minute: 30),
    );
    await open(tester);

    await tester.tap(find.text('Um 07:30 Uhr'));
    await tester.pumpAndSettle();

    expect(find.text('07'), findsOneWidget);
    expect(find.text('30'), findsWidgets);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    await drain(tester);
  });

  testWidgets('a second one lives next to the first', (tester) async {
    await seed(const Reminder(days: {1, 2, 3, 4, 5}, hour: 8, minute: 0));
    await open(tester);

    await tester.tap(find.text('Erinnerung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(await stored(), hasLength(2));
    // Five weekday alarms plus one daily.
    expect(channels.scheduled, hasLength(6));
    await drain(tester);
  });

  testWidgets('removing the last one clears the queue', (tester) async {
    await seed(
      const Reminder(days: {1, 2, 3, 4, 5, 6, 7}, hour: 7, minute: 30),
    );
    await open(tester);

    await tester.tap(find.byTooltip('Erinnerung entfernen'));
    await tester.pumpAndSettle();

    expect(await stored(), isEmpty);
    expect(channels.scheduled, isEmpty);
    // Only the alarms go, a running download keeps its notification.
    expect(
      channels.calls,
      contains(
        'dexterous.com/flutter/local_notifications.pendingNotificationRequests',
      ),
    );
    expect(
      channels.calls,
      isNot(contains('dexterous.com/flutter/local_notifications.cancelAll')),
    );
    await drain(tester);
  });

  testWidgets('without permission it says so', (tester) async {
    channels.notificationsAllowed = false;
    await open(tester);

    await tester.tap(find.text('Erinnerung einrichten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      find.text('Die Benachrichtigungen müssen für diese App erlaubt werden.'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('shows what is set up', (tester) async {
    await seed(const Reminder(days: {1, 2, 3, 4, 5}, hour: 8, minute: 0));
    await seed(const Reminder(days: {6, 7}, hour: 11, minute: 0));
    await open(tester);

    expect(find.text('Um 08:00 Uhr'), findsOneWidget);
    expect(find.text('Um 11:00 Uhr'), findsOneWidget);
    expect(find.byTooltip('Erinnerung entfernen'), findsNWidgets(2));
    await drain(tester);
  });

  testWidgets('a reminder only counts its own list', (tester) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Tschüss', currentVideo: sampleVideo),
      sampleEntry(id: 3, text: 'Baum', currentVideo: sampleVideo),
    ]);
    await addToList(db, list.id, [1]);
    // The body counts what is due, and a fresh card is new rather than due.
    final card = await getOrCreateCard(db, 1, Direction.recognition);
    await db
        .into(db.cards)
        .insertOnConflictUpdate(
          card.copyWith(
            state: 2,
            stability: const Value(4),
            difficulty: const Value(5),
            due: DateTime.now().subtract(const Duration(days: 1)),
            lastReview: Value(DateTime.now().subtract(const Duration(days: 2))),
            reps: 1,
          ),
        );
    await open(tester);

    await tester.tap(find.text('Erinnerung einrichten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // One word in the list, not the three in the cache.
    expect(channels.scheduled.single['body'], contains('1'));
    await drain(tester);
  });

  testWidgets('deleting the list takes its reminders with it', (tester) async {
    await seed(const Reminder(days: {1}, hour: 8, minute: 0));
    await deleteList(db, list.id);

    expect(await remindersFor(db, list.id), isEmpty);
    expect(await allReminders(db), isEmpty);
  });
}
