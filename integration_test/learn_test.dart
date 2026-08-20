import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:integration_test/integration_test.dart';

/// The trainer end to end on a device:
///   flutter test integration_test/learn_test.dart -d `device`
///
/// The host suite covers the same rules against fakes. This one runs them
/// through the real shell, the real router and the real video stack, which is
/// where the scope switch and the per-list budget actually live.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  const video = ApiVideo(
    id: 951,
    videoUrl: 'https://assets.wishlephant.com/signdict/videos/x.mp4',
    // No thumbnail on purpose. On a device the image is really fetched, and a
    // fabricated url would only make the harness report the 403 that the app
    // itself shrugs off.
    thumbnailUrl: null,
    license: 'by-sa/3.0/de',
    copyright: 'Philipps',
    updatedAt: '2017-05-07 10:52:00',
    userName: 'Wikisign DGS',
  );

  ApiEntry entry(int id, String text, {bool withVideo = true}) => ApiEntry(
    id: id,
    text: text,
    type: 'word',
    language: 'DGS',
    currentVideo: withVideo ? video : null,
  );

  setUp(() async {
    db = AppDatabase.forTesting();
    downloads = Downloads(db);

    // forTesting() is a real file on the device and outlives the run.
    await db.delete(db.reviews).go();
    await db.delete(db.cards).go();
    await db.delete(db.listItems).go();
    await db.delete(db.lists).go();
    await db.delete(db.entries).go();
    await db.delete(db.settings).go();
    // Without the marker the app walks the whole index over the network and
    // the counts below would drift with it.
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          const StoredSetting(key: 'index:synced', value: true),
        );
    // The tour is a first start only. It would cover the shell these cases
    // drive.
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          const StoredSetting(key: 'tourDone', value: true),
        );
    await ensureSystemLists(db);

    settings = AppSettings(db);
    await settings.load();
  });

  tearDown(() => db.close());

  Future<void> seed(int count, {bool withVideo = true}) => cacheEntries(db, [
    for (var i = 1; i <= count; i++) entry(i, 'Wort $i', withVideo: withVideo),
  ]);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      GebaerdenApp(db: db, settings: settings, network: NetworkStatus()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('Lernen').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> reach(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find.byType(Scrollable).first,
    );
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await reach(tester, find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Self rating hides the grades until the word is shown.
  Future<void> answer(WidgetTester tester, String grade) async {
    await pick(tester, 'Auflösen');
    await pick(tester, grade);
  }

  testWidgets('an empty deck offers nothing to start', (tester) async {
    await open(tester);

    expect(find.textContaining('nichts fällig'), findsOneWidget);
    expect(find.text('Loslegen'), findsNothing);
  });

  testWidgets('words without a video never reach the trainer', (tester) async {
    await seed(4, withVideo: false);
    await open(tester);

    expect(find.textContaining('nichts fällig'), findsOneWidget);
  });

  testWidgets('the scope walks from all words to a list and back', (
    tester,
  ) async {
    await seed(5);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1, 2]);

    await open(tester);
    expect(find.text('Alle Wörter'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    await pick(tester, 'Küche');
    expect(find.text('2'), findsOneWidget);
    expect(find.text('5'), findsNothing);

    // The way back was the whole point of the report.
    await pick(tester, 'Alle Wörter');
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('an empty list says so instead of falling back', (tester) async {
    await seed(3);
    await createList(db, 'Leer');

    await open(tester);
    await pick(tester, 'Leer');

    expect(find.textContaining('nichts fällig'), findsOneWidget);
    expect(find.text('Loslegen'), findsNothing);
  });

  testWidgets('a list budget caps the session and leaves the rest alone', (
    tester,
  ) async {
    await seed(6);
    final one = await createList(db, 'Eins');
    final two = await createList(db, 'Zwei');
    await addToList(db, one.id, [1, 2, 3]);
    await addToList(db, two.id, [4, 5, 6]);
    await setListLimits(db, one.id, newPerDay: 1);

    await open(tester);
    await pick(tester, 'Eins');
    await pick(tester, 'Loslegen');

    // One card, so the counter says one left.
    expect(find.text('1 übrig'), findsOneWidget);
    await answer(tester, 'Gut');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The other list still has its own budget untouched.
    await pick(tester, 'Zwei');
    await pick(tester, 'Loslegen');
    expect(find.text('3 übrig'), findsOneWidget);
  });

  testWidgets('the budget goes back to the setting', (tester) async {
    await seed(3);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);
    await setListLimits(db, list.id, newPerDay: 7, reviewPerDay: 9);

    await open(tester);
    await pick(tester, 'Küche');
    await pick(tester, 'Vorgabe verwenden');

    final row = (await allLists(db)).firstWhere((l) => l.id == list.id);
    expect(row.newPerDay, isNull);
    expect(row.reviewPerDay, isNull);
    expect(find.text('Vorgabe verwenden'), findsNothing);
  });

  testWidgets('answering walks the deck down and ends the session', (
    tester,
  ) async {
    await seed(2);
    await open(tester);
    await pick(tester, 'Loslegen');

    expect(find.text('2 übrig'), findsOneWidget);
    await answer(tester, 'Gut');
    expect(find.text('1 übrig'), findsOneWidget);
    await answer(tester, 'Gut');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Back in the lobby, both answered.
    expect(find.text('Umfang'.toUpperCase()), findsOneWidget);
    expect((await db.select(db.reviews).get()).length, 2);
  });

  testWidgets('again puts the card back into the same session', (tester) async {
    await seed(1);
    await open(tester);
    await pick(tester, 'Loslegen');

    expect(find.text('1 übrig'), findsOneWidget);
    await answer(tester, 'Nochmal');

    // Still running, the card came back rather than ending the session.
    expect(find.text('1 übrig'), findsOneWidget);
  });

  testWidgets('undo takes the last answer back', (tester) async {
    await seed(2);
    await open(tester);
    await pick(tester, 'Loslegen');
    await answer(tester, 'Gut');
    expect(find.text('1 übrig'), findsOneWidget);

    await tester.tap(find.byTooltip('Letzte Antwort zurücknehmen'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('2 übrig'), findsOneWidget);
    expect(await db.select(db.reviews).get(), isEmpty);
  });

  testWidgets('a word marked known drops out of the deck', (tester) async {
    await seed(2);
    await open(tester);
    await pick(tester, 'Loslegen');

    await tester.tap(find.byTooltip('Kenne ich schon'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('1 übrig'), findsOneWidget);
    expect(await listEntryIds(db, knownList), hasLength(1));
  });

  testWidgets('both directions ask every word twice', (tester) async {
    await seed(3);
    await open(tester);
    expect(find.text('3'), findsOneWidget);

    await pick(tester, 'Beides');
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('the typing mode forgives ae for ä', (tester) async {
    await cacheEntries(db, [entry(1, 'Bär')]);
    await open(tester);
    await pick(tester, 'Tippen');
    await pick(tester, 'Loslegen');

    await tester.enterText(find.byType(TextField), 'Baer');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // A wrong answer names the word instead, and grades again.
    expect(find.textContaining('Richtig ist'), findsNothing);
    final logged = await db.select(db.reviews).get();
    expect(logged.single.rating, f.Rating.good.value);
  });

  testWidgets('the choice mode offers four answers', (tester) async {
    await seed(20);
    await open(tester);
    await pick(tester, 'Auswahl');
    await pick(tester, 'Loslegen');

    expect(find.byType(InkWell), findsWidgets);
    final words = find.textContaining(RegExp(r'^Wort \d+$')).evaluate().length;
    expect(words, 4);
  });

  testWidgets('a suspended card stays out', (tester) async {
    await seed(2);
    final card = await getOrCreateCard(db, 1, Direction.recognition);
    await db
        .into(db.cards)
        .insertOnConflictUpdate(card.copyWith(suspended: true));

    await open(tester);
    expect(find.text('1'), findsOneWidget);
  });
}
