import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/reminders.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/platform/notify.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/transfer/backup.dart';
import 'package:integration_test/integration_test.dart';

/// Lists, their reminders and the backup on a device:
///   flutter test integration_test/lists_test.dart -d `device`
///
/// The reminders go through the real plugin, so the alarms below are the ones
/// the system actually holds. Needs POST_NOTIFICATIONS granted while the run
/// is up, see AGENTS.md.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  const video = ApiVideo(
    id: 951,
    videoUrl: 'https://assets.wishlephant.com/signdict/videos/x.mp4',
    thumbnailUrl: null,
    license: 'by-sa/3.0/de',
    copyright: 'Philipps',
    updatedAt: '2017-05-07 10:52:00',
    userName: 'Wikisign DGS',
  );

  ApiEntry entry(int id, String text) => ApiEntry(
    id: id,
    text: text,
    type: 'word',
    language: 'DGS',
    currentVideo: video,
  );

  /// A card that is really due, so the reminder text carries a number.
  Future<void> due(int entryId) async {
    final card = await getOrCreateCard(db, entryId, Direction.recognition);
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
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    downloads = Downloads(db);
    await initNotifications();
    await cancelReminders();

    await db.delete(db.reminders).go();
    await db.delete(db.reviews).go();
    await db.delete(db.cards).go();
    await db.delete(db.listItems).go();
    await db.delete(db.lists).go();
    await db.delete(db.entries).go();
    await db.delete(db.settings).go();
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          const StoredSetting(key: 'index:synced', value: true),
        );
    await ensureSystemLists(db);

    settings = AppSettings(db);
    await settings.load();
  });

  tearDown(() async {
    await cancelReminders();
    await db.close();
  });

  testWidgets('a reminder lands in the system queue with its own count', (
    _,
  ) async {
    await cacheEntries(db, [entry(1, 'Hallo'), entry(2, 'Tschüss')]);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);
    await due(1);
    await due(2);

    await addReminder(
      db,
      list.id,
      const Reminder(days: {1, 2, 3, 4, 5}, hour: 19, minute: 30),
    );
    final ok = await scheduleReminders(
      await dueReminders(db, const [Direction.recognition]),
    );
    expect(ok, isTrue, reason: 'without the permission this fails');

    // Five weekdays, five alarms.
    final pending = await pendingReminders();
    expect(pending, hasLength(5));
    // One card in the list, not the two in the cache.
    expect(pending.first.body, contains('1'));
    expect(pending.first.payload, 'lernen:${list.id}');
  });

  testWidgets('two lists keep their own reminders and counts', (_) async {
    await cacheEntries(db, [entry(1, 'Hallo'), entry(2, 'Tschüss')]);
    final one = await createList(db, 'Eins');
    final two = await createList(db, 'Zwei');
    await addToList(db, one.id, [1]);
    await addToList(db, two.id, [1, 2]);
    await due(1);
    await due(2);

    await addReminder(
      db,
      one.id,
      const Reminder(days: {1}, hour: 8, minute: 0),
    );
    await addReminder(
      db,
      two.id,
      const Reminder(days: {2}, hour: 9, minute: 0),
    );
    await scheduleReminders(
      await dueReminders(db, const [Direction.recognition]),
    );

    final pending = await pendingReminders();
    expect(pending, hasLength(2));
    final bodies = {for (final p in pending) p.payload: p.body};
    expect(bodies['lernen:${one.id}'], contains('1'));
    expect(bodies['lernen:${two.id}'], contains('2'));
  });

  testWidgets('deleting a list takes its alarms with it', (_) async {
    await cacheEntries(db, [entry(1, 'Hallo')]);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);
    await due(1);

    await addReminder(
      db,
      list.id,
      const Reminder(days: {1, 2}, hour: 8, minute: 0),
    );
    await scheduleReminders(
      await dueReminders(db, const [Direction.recognition]),
    );
    expect(await pendingReminders(), hasLength(2));

    await deleteList(db, list.id);
    await refreshReminders(
      await dueReminders(db, const [Direction.recognition]),
    );
    // Nothing left to schedule, so nothing is queued either.
    expect(await allReminders(db), isEmpty);
    await cancelReminders();
    expect(await pendingReminders(), isEmpty);
  });

  testWidgets('a tap on a reminder opens the trainer of its list', (
    tester,
  ) async {
    await cacheEntries(db, [entry(1, 'Hallo'), entry(2, 'Tschüss')]);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);

    await tester.pumpWidget(
      GebaerdenApp(db: db, settings: settings, network: NetworkStatus()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // What the plugin hands over when the notification is tapped.
    expect(reminderTapHandler, isNotNull);
    reminderTapHandler!(list.id);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The lobby of that list: its own scope is the marked one.
    expect(find.text('Küche'), findsWidgets);
    expect(find.text('Umfang'.toUpperCase()), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a backup carries only the ticked sections', (_) async {
    await cacheEntries(db, [entry(1, 'Hallo')]);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);
    await due(1);
    await addReminder(
      db,
      list.id,
      const Reminder(days: {3}, hour: 7, minute: 0),
    );

    final onlyLists = await exportBackup(
      db,
      sections: const {BackupSection.lists},
    );
    expect(sectionsIn(onlyLists), const {BackupSection.lists});

    final everything = await exportBackup(db);
    expect(sectionsIn(everything), hasLength(4));
  });

  testWidgets('an import takes only what was ticked', (_) async {
    await cacheEntries(db, [entry(1, 'Hallo')]);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);
    await due(1);
    await addReminder(
      db,
      list.id,
      const Reminder(days: {3}, hour: 7, minute: 0),
    );
    final text = await exportBackup(db);

    await db.delete(db.reminders).go();
    await db.delete(db.cards).go();
    await db.delete(db.listItems).go();
    await db.delete(db.lists).go();

    await importBackup(
      db,
      text,
      ImportMode.merge,
      sections: const {BackupSection.lists, BackupSection.reminders},
    );

    expect((await allLists(db)).any((l) => l.name == 'Küche'), isTrue);
    expect(await allReminders(db), hasLength(1));
    // Progress was left unticked, so it stays gone.
    expect(await db.select(db.cards).get(), isEmpty);
  });

  testWidgets('the reminders survive a round trip', (_) async {
    final list = await createList(db, 'Küche');
    await addReminder(
      db,
      list.id,
      const Reminder(days: {1, 3, 5}, hour: 6, minute: 45),
    );
    final text = await exportBackup(db);

    await db.delete(db.reminders).go();
    await importBackup(db, text, ImportMode.merge);

    final back = (await allReminders(db)).single;
    expect(back.listId, list.id);
    expect(back.reminder.days, {1, 3, 5});
    expect(back.reminder.time, '06:45');
  });
}
