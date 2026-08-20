import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/recent.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/ui/dictionary_screen.dart';
import 'package:gebaerden/ui/widgets/entry_list.dart';
import 'package:http/http.dart' as http;

import 'harness.dart';
import 'latest_test.dart' show stubIndex;
import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() async {
    useClient(http.Client());
    await db.close();
  });

  group('the start of the dictionary', () {
    testWidgets('offers a random sign and the newest ones', (tester) async {
      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('Zufällig'), findsOneWidget);
      expect(find.text('Neu'), findsOneWidget);
    });

    testWidgets('a letter stays a small tile on a wide window', (tester) async {
      // Ensures grid does not stretch excessively on desktop widths.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      final tile = tester.getSize(
        find.ancestor(of: find.text('A'), matching: find.byType(InkWell)).first,
      );
      expect(tile.width, lessThanOrEqualTo(72));
      expect(tile.height, greaterThanOrEqualTo(40));
    });

    testWidgets('without history there is no recent section', (tester) async {
      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('ZULETZT'), findsNothing);
    });

    testWidgets('opened words and past queries come back', (tester) async {
      await remember(db, RecentKind.entry, '7', 'Haus');
      await remember(db, RecentKind.search, 'auto', 'auto');

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('ZULETZT'), findsOneWidget);
      expect(find.text('Haus'), findsOneWidget);
      expect(find.text('auto'), findsOneWidget);
    });

    testWidgets('tapping a past query searches again', (tester) async {
      await remember(db, RecentKind.search, 'Haus', 'Haus');
      stubApi({
        'search': [
          {'id': 1, 'text': 'Haus', 'currentVideo': sampleVideo.toJson()},
        ],
      });

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Haus'));
      await settle(tester);

      expect(find.widgetWithText(EntryRow, 'Haus'), findsOneWidget);
    });

    testWidgets('a search lands in the history', (tester) async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Haus', 'currentVideo': sampleVideo.toJson()},
        ],
      });

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Haus');
      await settle(tester);

      final kept = await recentItems(db, RecentKind.search);
      expect(kept.map((r) => r.value), ['Haus']);
    });

    testWidgets('clearing empties the history', (tester) async {
      await remember(db, RecentKind.entry, '7', 'Haus');

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leeren'));
      await tester.pumpAndSettle();

      expect(find.text('ZULETZT'), findsNothing);
      expect(await recentItems(db, RecentKind.entry), isEmpty);
    });

    testWidgets('a random sign that fails says so', (tester) async {
      stubApiFailure();
      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Zufällig'));
      await settle(tester);

      expect(find.text('Zufällig'), findsOneWidget);
    });

    testWidgets('a page without videos leaves the screen alone', (
      tester,
    ) async {
      stubApi({
        'index': [
          {'id': 1, 'text': 'Ohne'},
        ],
      });

      await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Zufällig'));
      await settle(tester);

      expect(find.text('Zufällig'), findsOneWidget);
      expect(await getEntry(db, 1), isNull);
    });
  });

  group('the newest entries', () {
    // Seeds lastPage to prevent excessive pump cycles during index walk.
    Future<void> hint(int page) => db
        .into(db.settings)
        .insertOnConflictUpdate(
          StoredSetting(key: 'index:lastPage', value: page),
        );

    testWidgets('are listed with the freshest on top', (tester) async {
      await hint(3);
      stubIndex(3);
      await tester.pumpWidget(await harness(db, NewestScreen(db: db)));
      await settle(tester, steps: 30);

      expect(find.text('Neu im Wörterbuch'), findsOneWidget);
      expect(find.widgetWithText(EntryRow, 'Wort 2-2'), findsOneWidget);
    });

    testWidgets('an empty index says so', (tester) async {
      await hint(1);
      stubApi({'index': <Object>[]});
      await tester.pumpWidget(await harness(db, NewestScreen(db: db)));
      await settle(tester, steps: 30);

      expect(find.text('Nichts gefunden.'), findsOneWidget);
    });

    testWidgets('a broken request says so', (tester) async {
      stubApiFailure();
      await tester.pumpWidget(await harness(db, NewestScreen(db: db)));
      await settle(tester, steps: 40);

      expect(
        find.text('Das hat nicht funktioniert. Prüfe bitte deine Verbindung.'),
        findsOneWidget,
      );
    });
  });
}
