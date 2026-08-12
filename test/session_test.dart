import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/ui/learn_screen.dart';
import 'package:gebaerden/ui/lists_screen.dart';
import 'package:gebaerden/ui/widgets/stats_panel.dart';

import 'harness.dart';
import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  Future<void> seed(int count) async {
    await cacheEntries(db, [
      for (var i = 1; i <= count; i++)
        sampleEntry(id: i, text: 'Wort $i', currentVideo: sampleVideo),
    ]);
  }

  group('a running session', () {
    testWidgets('shows how many are left and can be ended', (tester) async {
      await seed(3);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loslegen'));
      await settle(tester);

      expect(find.text('3 übrig'), findsOneWidget);
      expect(find.text('Auflösen'), findsOneWidget);

      await tester.tap(find.text('Beenden'));
      await settle(tester);
      expect(find.text('Loslegen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('answering shortens the queue and logs a review', (
      tester,
    ) async {
      await seed(3);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loslegen'));
      await settle(tester);
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gut'));
      await settle(tester);

      expect(find.text('2 übrig'), findsOneWidget);
      expect(await db.select(db.reviews).get(), hasLength(1));
      await drain(tester);
    });

    testWidgets('a second tap on the same answer changes nothing', (
      tester,
    ) async {
      await seed(3);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loslegen'));
      await settle(tester);
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();

      // Both land before the write is back, so the second one has to be
      // ignored. Counting it would log the card twice and skip the next.
      await tester.tap(find.text('Gut'), warnIfMissed: false);
      await tester.tap(find.text('Gut'), warnIfMissed: false);
      await settle(tester);

      expect(await db.select(db.reviews).get(), hasLength(1));
      expect(find.text('2 übrig'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('again puts the card back instead of dropping it', (
      tester,
    ) async {
      await seed(3);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loslegen'));
      await settle(tester);
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nochmal'));
      await settle(tester);

      expect(find.text('3 übrig'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('undo takes the answer back, in the queue and on disk', (
      tester,
    ) async {
      await seed(3);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loslegen'));
      await settle(tester);
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gut'));
      await settle(tester);
      expect(await db.select(db.reviews).get(), hasLength(1));

      await tester.tap(find.byTooltip('Letzte Antwort zurücknehmen'));
      await settle(tester);

      expect(find.text('3 übrig'), findsOneWidget);
      expect(await db.select(db.reviews).get(), isEmpty);
      await drain(tester);
    });

    testWidgets('known drops the word out of the session', (tester) async {
      await seed(3);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loslegen'));
      await settle(tester);
      await tester.tap(find.byTooltip('Kenne ich schon'));
      await settle(tester);

      expect(find.text('2 übrig'), findsOneWidget);
      expect(await listEntryIds(db, knownList), hasLength(1));
      await drain(tester);
    });

    testWidgets('the daily limit caps the queue', (tester) async {
      await seed(30);
      final settings = AppSettings(db);
      await settings.load();
      await settings.set('newPerDay', 4);

      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loslegen'));
      await settle(tester);

      expect(find.text('4 übrig'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('what was answered today counts against the limit', (
      tester,
    ) async {
      await seed(30);
      final settings = AppSettings(db);
      await settings.load();
      await settings.set('newPerDay', 4);

      // Two new cards already answered today.
      for (final id in [1, 2]) {
        await gradeCard(
          db,
          await getOrCreateCard(db, id, Direction.recognition),
          f.Rating.good,
        );
      }

      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loslegen'));
      await settle(tester);

      expect(find.text('2 übrig'), findsOneWidget);
      await drain(tester);
    });
  });

  group('list detail', () {
    testWidgets('lists the words and offers to learn them', (tester) async {
      await seed(2);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1, 2]);

      await tester.pumpWidget(
        await harness(db, ListScreen(db: db, id: list.id)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Küche'), findsOneWidget);
      expect(find.text('Wort 1'), findsOneWidget);
      expect(find.text('Diese Liste lernen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('an empty list says so', (tester) async {
      final list = await createList(db, 'Leer');
      await tester.pumpWidget(
        await harness(db, ListScreen(db: db, id: list.id)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Noch keine Wörter'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('removing a word updates the list at once', (tester) async {
      await seed(2);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1, 2]);

      await tester.pumpWidget(
        await harness(db, ListScreen(db: db, id: list.id)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Wort 1 aus der Liste entfernen'));
      await tester.pumpAndSettle();

      expect(find.text('Wort 1'), findsNothing);
      expect(find.text('Wort 2'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a built-in list cannot be renamed or deleted', (tester) async {
      await tester.pumpWidget(
        await harness(db, ListScreen(db: db, id: knownList)),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Liste teilen'), findsOneWidget);
      expect(find.byTooltip('Liste umbenennen'), findsNothing);
      expect(find.byTooltip('Liste löschen'), findsNothing);
      await drain(tester);
    });
  });

  group('stats', () {
    testWidgets('shows the streak and both charts once there are cards', (
      tester,
    ) async {
      await seed(1);
      await gradeCard(
        db,
        await getOrCreateCard(db, 1, Direction.recognition),
        f.Rating.good,
      );

      await tester.pumpWidget(await harness(db, StatsPanel(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('TAGE IN FOLGE'), findsOneWidget);
      expect(find.text('GELERNT'), findsOneWidget);
      expect(find.text('LETZTE 14 TAGE'), findsOneWidget);
      expect(find.text('KOMMENDE 7 TAGE'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a due card shows up in the forecast', (tester) async {
      await seed(1);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      await db
          .into(db.cards)
          .insertOnConflictUpdate(
            card.copyWith(
              stability: const Value(10),
              difficulty: const Value(5),
              state: f.State.review.value,
              due: DateTime.now(),
            ),
          );

      await tester.pumpWidget(await harness(db, StatsPanel(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('KOMMENDE 7 TAGE'), findsOneWidget);
      await drain(tester);
    });
  });
}
