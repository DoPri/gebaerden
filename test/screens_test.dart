import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/ui/dictionary_screen.dart';
import 'package:gebaerden/ui/learn_screen.dart';
import 'package:gebaerden/ui/lists_screen.dart';
import 'package:gebaerden/ui/more_screen.dart';
import 'package:gebaerden/ui/offline_screen.dart';
import 'package:gebaerden/ui/shell.dart';
import 'package:gebaerden/ui/widgets/entry_list.dart';
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

  group('dictionary', () {
    testWidgets('an empty query shows the letters', (tester) async {
      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('Nach Buchstabe'.toUpperCase()), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('a query shows what the server sends', (tester) async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Haus', 'currentVideo': sampleVideo.toJson()},
        ],
      });

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Haus');
      await settle(tester);

      // The query itself sits in the field, so look inside a row.
      expect(find.widgetWithText(EntryRow, 'Haus'), findsOneWidget);
    });

    testWidgets('a failed request says so', (tester) async {
      stubApiFailure();

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Haus');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.textContaining('nicht funktioniert'), findsOneWidget);
    });

    testWidgets('entries without video stay hidden by default', (tester) async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Beispielsatz'},
        ],
      });

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Beispiel');
      await settle(tester);

      expect(find.text('Beispielsatz'), findsNothing);
      expect(find.textContaining('keine Videos'), findsOneWidget);
    });
  });

  group('learn', () {
    testWidgets('counts what is waiting and offers the three modes', (
      tester,
    ) async {
      await seed(5);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
      for (final mode in ['Selbst', 'Auswahl', 'Tippen']) {
        expect(find.text(mode), findsOneWidget);
      }
      expect(find.text('Loslegen'), findsOneWidget);
    });

    testWidgets('an empty deck explains itself instead of offering a start', (
      tester,
    ) async {
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('Loslegen'), findsNothing);
      expect(find.textContaining('nichts fällig'), findsOneWidget);
    });

    testWidgets('the counts follow the dictionary arriving afterwards', (
      tester,
    ) async {
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();
      expect(find.textContaining('nichts fällig'), findsOneWidget);

      // On a fresh install the dictionary is fetched in the background and
      // lands after this tab has already counted. It used to stay on zero.
      await seed(3);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('Loslegen'), findsOneWidget);
    });

    testWidgets('the scope offers all words next to every list', (
      tester,
    ) async {
      await seed(3);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1]);

      await tester.pumpWidget(
        await harness(db, LearnScreen(db: db, listId: list.id)),
      );
      await tester.pumpAndSettle();

      // The way back was missing entirely once a list was picked.
      expect(find.text('Alle Wörter'), findsOneWidget);
      expect(find.text('Küche'), findsOneWidget);
    });

    testWidgets('a list counts only its own words', (tester) async {
      await seed(5);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1, 2]);

      await tester.pumpWidget(
        await harness(db, LearnScreen(db: db, listId: list.id)),
      );
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('a list keeps its own daily budget', (tester) async {
      await seed(3);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1]);
      await setListLimits(db, list.id, newPerDay: 7, reviewPerDay: 9);

      await tester.pumpWidget(
        await harness(db, LearnScreen(db: db, listId: list.id)),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Tageslimits dieser Liste'.toUpperCase()),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.widgetWithText(TextFormField, '7'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '9'), findsOneWidget);
    });

    testWidgets('a budget typed into the list is kept there', (tester) async {
      await seed(3);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1]);

      await tester.pumpWidget(
        await harness(db, LearnScreen(db: db, listId: list.id)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Tageslimits dieser Liste'.toUpperCase()),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // The two fields start on the global setting.
      await tester.enterText(find.widgetWithText(TextFormField, '20'), '4');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '200'), '8');
      await tester.pumpAndSettle();

      final row = (await allLists(db)).firstWhere((l) => l.id == list.id);
      expect(row.newPerDay, 4);
      expect(row.reviewPerDay, 8);
      expect(find.text('Vorgabe verwenden'), findsOneWidget);
    });

    testWidgets('switching the scope recounts', (tester) async {
      await seed(5);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1]);

      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);

      // go_router keeps the State and swaps the widget, so the counts have to
      // follow from didUpdateWidget or they stay on the old scope.
      await tester.pumpWidget(
        await harness(db, LearnScreen(db: db, listId: list.id)),
      );
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('the budget can be handed back to the setting', (tester) async {
      await seed(3);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1]);
      await setListLimits(db, list.id, newPerDay: 7, reviewPerDay: 9);

      await tester.pumpWidget(
        await harness(db, LearnScreen(db: db, listId: list.id)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Vorgabe verwenden'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Vorgabe verwenden'));
      await tester.pumpAndSettle();

      final row = (await allLists(db)).firstWhere((l) => l.id == list.id);
      expect(row.newPerDay, isNull);
      expect(row.reviewPerDay, isNull);
      expect(find.text('Vorgabe verwenden'), findsNothing);
      expect(find.widgetWithText(TextFormField, '20'), findsOneWidget);
    });

    testWidgets('without a list there is no per-list budget', (tester) async {
      await seed(3);
      await createList(db, 'Küche');

      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('Tageslimits dieser Liste'.toUpperCase()), findsNothing);
    });

    testWidgets('picking a mode keeps it', (tester) async {
      await seed(3);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tippen'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Tippe das Wort ein'), findsOneWidget);
    });

    testWidgets('both directions doubles the count', (tester) async {
      await seed(4);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('4'), findsOneWidget);
      await tester.tap(find.text('Beides'));
      await tester.pumpAndSettle();
      expect(find.text('8'), findsOneWidget);
    });
  });

  group('lists', () {
    testWidgets('shows the built-ins with their counts', (tester) async {
      await tester.pumpWidget(await harness(db, ListsScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('Kenne ich schon'), findsOneWidget);
      expect(find.text('Favoriten'), findsOneWidget);
      expect(find.text('Lernen'), findsOneWidget);
    });

    testWidgets('creating one adds it without a reload', (tester) async {
      await tester.pumpWidget(await harness(db, ListsScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Neue Liste'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Küche');
      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();

      expect(find.text('Küche'), findsOneWidget);
    });

    testWidgets('deleting elsewhere reaches the overview', (tester) async {
      final list = await createList(db, 'Weg');
      await tester.pumpWidget(await harness(db, ListsScreen(db: db)));
      await tester.pumpAndSettle();
      expect(find.text('Weg'), findsOneWidget);

      await deleteList(db, list.id);
      await tester.pumpAndSettle();
      expect(find.text('Weg'), findsNothing);
    });
  });

  group('more', () {
    testWidgets('renders the settings', (tester) async {
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('System'), findsOneWidget);
      expect(find.text('Neue Karten'), findsOneWidget);

      // The reminder moved onto the list it belongs to.
      expect(find.text('Erinnerung einrichten'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Exportieren'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Exportieren'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a changed limit is written through', (tester) async {
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '20'), '7');
      await tester.pumpAndSettle();

      final again = AppSettings(db);
      await again.load();
      expect(again.newPerDay, 7);
      await drain(tester);
    });
  });

  group('offline', () {
    testWidgets('shows nothing stored and the packages', (tester) async {
      await tester.pumpWidget(await harness(db, OfflineScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('0 B'), findsOneWidget);
      expect(find.text('Alle Gebärden'), findsOneWidget);
      expect(find.text('Leeren'), findsNothing);
      // drift schedules a zero timer when a stream is cancelled.
      await drain(tester);
    });
  });

  group('shell', () {
    testWidgets('four tabs, the offline one is gone', (tester) async {
      await tester.pumpWidget(
        await harness(
          db,
          Shell(
            index: 0,
            onSelect: (_) {},
            title: 'Wörterbuch',
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tabs, hasLength(4));
      expect(find.text('Offline'), findsNothing);
      expect(find.text('Mehr'), findsOneWidget);
    });

    testWidgets('says so when there is no network', (tester) async {
      await tester.pumpWidget(
        await harness(
          db,
          Shell(
            index: 0,
            onSelect: (_) {},
            title: 'Wörterbuch',
            child: const SizedBox.shrink(),
          ),
          online: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Keine Internetverbindung'), findsOneWidget);
    });
  });

  group('stats', () {
    testWidgets('stays out of the way with no cards', (tester) async {
      await tester.pumpWidget(await harness(db, StatsPanel(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('Tage in Folge'.toUpperCase()), findsNothing);
    });
  });
}
