import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/media/variants.dart';
import 'package:gebaerden/srs/charset.dart';
import 'package:gebaerden/ui/charset_screen.dart';
import 'package:gebaerden/ui/entry_screen.dart';
import 'package:gebaerden/ui/widgets/list_picker.dart';
import 'package:gebaerden/ui/widgets/variant_list.dart';

import 'harness.dart';
import 'support.dart';

const _other = ApiVideo(
  id: 4711,
  videoUrl: 'https://example.invalid/other.mp4',
  thumbnailUrl: 'https://example.invalid/other.jpg',
  license: 'by-nc-sa/4.0',
  updatedAt: '2020-05-07 10:52:00',
  userName: 'GebLex',
);

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  group('variant list', () {
    testWidgets('names every source with its license', (tester) async {
      var picked = -1;
      await tester.pumpWidget(
        await harness(
          db,
          VariantList(
            db: db,
            videos: const [sampleVideo, _other],
            selected: 0,
            word: 'Haus',
            onSelect: (i) => picked = i,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 Varianten für »Haus«'.toUpperCase()), findsOneWidget);
      expect(find.text('Wikisign DGS'), findsOneWidget);
      expect(find.text('GebLex'), findsOneWidget);
      expect(find.textContaining('CC BY-NC-SA 4.0'), findsOneWidget);

      await tester.tap(find.text('GebLex'));
      expect(picked, 1);
    });

    testWidgets('marks the picked one', (tester) async {
      await tester.pumpWidget(
        await harness(
          db,
          VariantList(
            db: db,
            videos: const [sampleVideo, _other],
            selected: 1,
            word: 'Haus',
            onSelect: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        find.textContaining('Deine Auswahl wird dauerhaft gespeichert'),
        findsOneWidget,
      );
    });
  });

  group('list picker', () {
    testWidgets('toggles membership and shows it', (tester) async {
      await cacheEntries(db, [sampleEntry(currentVideo: sampleVideo)]);
      await tester.pumpWidget(
        await harness(db, ListPicker(db: db, entryId: 835)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Favoriten'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);

      await tester.tap(find.text('Favoriten'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(await listsContaining(db, 835), contains('favourites'));
    });
  });

  group('entry screen', () {
    testWidgets('says so when there is no video', (tester) async {
      stubApi({
        'entry': {'id': 835, 'text': 'Beispielsatz'},
      });
      await tester.pumpWidget(await harness(db, EntryScreen(db: db, id: 835)));
      await settle(tester);

      expect(find.text('Beispielsatz'), findsOneWidget);
      expect(find.textContaining('noch kein Video'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a failed load says so instead of hanging', (tester) async {
      stubApiFailure();
      await tester.pumpWidget(await harness(db, EntryScreen(db: db, id: 835)));
      await settle(tester, steps: 20);

      expect(
        find.textContaining('konnte nicht geladen werden'),
        findsOneWidget,
      );
      await drain(tester);
    });

    testWidgets('an id the api does not know says so', (tester) async {
      stubApi({'entry': null});
      await tester.pumpWidget(
        await harness(db, EntryScreen(db: db, id: 999999)),
      );
      await settle(tester, steps: 20);

      expect(
        find.textContaining('konnte nicht geladen werden'),
        findsOneWidget,
      );
      await drain(tester);
    });

    testWidgets('picking a variant is remembered', (tester) async {
      stubApi({
        'entry': {
          'id': 835,
          'text': 'Haus',
          'currentVideo': sampleVideo.toJson(),
          'videos': [sampleVideo.toJson(), _other.toJson()],
        },
      });
      await tester.pumpWidget(await harness(db, EntryScreen(db: db, id: 835)));
      await settle(tester);

      await tester.scrollUntilVisible(
        find.text('GebLex'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('GebLex'));
      await settle(tester);

      final entry = await getEntry(db, 835);
      expect((await preferredVideo(db, entry!))!.id, _other.id);
      await drain(tester);
    });
  });

  group('charset screen', () {
    testWidgets('asks for a letter and offers four answers', (tester) async {
      // The mapping is cached, so no network round trip is needed.
      final chars = ['a', 'b', 'c', 'd', 'e'];
      final rows = await cacheEntries(db, [
        for (final (i, c) in chars.indexed)
          sampleEntry(id: 100 + i, text: c, currentVideo: sampleVideo),
      ]);
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            StoredSetting(
              key: 'charset:alphabet',
              value: {for (final (i, c) in chars.indexed) c: rows[i].id},
            ),
          );

      await tester.pumpWidget(
        await harness(db, CharsetScreen(db: db, charset: Charset.alphabet)),
      );
      await settle(tester);

      expect(find.text('Welcher Buchstabe ist das?'), findsOneWidget);
      final shown = chars.where(
        (c) => find.text(c.toUpperCase()).evaluate().isNotEmpty,
      );
      expect(shown, hasLength(4));
      await drain(tester);
    });

    testWidgets('numbers ask for a number', (tester) async {
      final chars = ['1', '2', '3', '4', '5'];
      final rows = await cacheEntries(db, [
        for (final (i, c) in chars.indexed)
          sampleEntry(id: 200 + i, text: c, currentVideo: sampleVideo),
      ]);
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            StoredSetting(
              key: 'charset:numbers',
              value: {for (final (i, c) in chars.indexed) c: rows[i].id},
            ),
          );

      await tester.pumpWidget(
        await harness(db, CharsetScreen(db: db, charset: Charset.numbers)),
      );
      await settle(tester);

      expect(find.text('Welche Zahl ist das?'), findsOneWidget);
      expect(find.text('Buchstabieren'), findsNothing);
      await drain(tester);
    });
  });
}
