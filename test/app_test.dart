import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
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
import 'package:gebaerden/transfer/list_file.dart';

import 'channels.dart';
import 'fake_storage.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late AppSettings settings;
  late Directory tmp;

  setUpAll(() {
    // Must happen before anything touches the singleton.
    FileDownloader(persistentStorage: MemoryStorage());
  });

  setUp(() async {
    db = testDb();
    channels = FakeChannels()..install();
    tmp = Directory.systemTemp.createTempSync('app_test');
    downloads = Downloads(db);
    settings = AppSettings(db);
    await settings.load();
    await initNotifications();
    // The app widget walks the index on the first start. An empty index ends
    // that walk at once. A failing one would be retried after a backoff and
    // that timer outlives the tree these tests tear down.
    stubApi({'index': <Object>[]});
  });

  tearDown(() async {
    channels.remove();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(
      GebaerdenApp(db: db, settings: settings, network: NetworkStatus()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('coming back rewrites the reminder with the new count', (
    tester,
  ) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    // The reminder counts its own list, so the card has to be in one.
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);
    await addReminder(
      db,
      list.id,
      const Reminder(days: {1, 2, 3, 4, 5, 6, 7}, hour: 19, minute: 0),
    );
    final card = await getOrCreateCard(db, 1, Direction.recognition);
    // A card that is really due, not a fresh one.
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

    await boot(tester);
    channels.scheduled.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(channels.scheduled, hasLength(1));
    expect(channels.scheduled.single['body'], contains('1'));
    await drain(tester);
  });

  testWidgets('without a reminder nothing is rescheduled', (tester) async {
    await boot(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(channels.scheduled, isEmpty);
    await drain(tester);
  });

  testWidgets('a file the system handed over opens the dialog', (tester) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    final list = await createList(db, 'Begrüßung');
    await addToList(db, list.id, [1]);

    final file = File('${tmp.path}/geteilt.dgsliste')
      ..writeAsStringSync(await encodeList(db, list));
    channels.shared = jsonEncode([
      {'path': file.path, 'type': 'file'},
    ]);

    await boot(tester);
    // Reading the file is real io, which needs the real clock.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Begrüßung'), findsOneWidget);
    expect(find.textContaining('Als neue Liste übernehmen?'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a tap on a reminder opens the trainer of its list', (
    tester,
  ) async {
    final list = await createList(db, 'Küche');
    await boot(tester);

    // What the notification hands over once the app is up.
    reminderTapHandler!(list.id);
    // The hop waits for the next frame and nothing else asks for one here.
    tester.binding.scheduleFrame();
    await tester.pumpAndSettle();

    expect(find.text('Alle Wörter'), findsOneWidget);
    expect(find.text('Küche'), findsWidgets);
    await drain(tester);
  });

  testWidgets('nothing shared means no dialog', (tester) async {
    await boot(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await drain(tester);
  });
}
