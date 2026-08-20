import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/platform/notify.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/transfer/backup.dart';
import 'package:gebaerden/ui/more_screen.dart';
import 'package:gebaerden/ui/widgets/entry_list.dart';
import 'package:http/http.dart' as http;

import 'channels.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late Directory tmp;

  setUp(() async {
    db = testDb();
    channels = FakeChannels()..install();
    tmp = Directory.systemTemp.createTempSync('more_test');
    // Mirrors main() startup initialization.
    await initNotifications();
  });

  tearDown(() async {
    useClient(http.Client());
    channels.remove();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester, Finder scrollTo) async {
    await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      scrollTo,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  group('the daily limits', () {
    testWidgets('the review limit sticks', (tester) async {
      await open(tester, find.text('Wiederholungen'));

      await tester.enterText(find.widgetWithText(TextFormField, '200'), '50');
      await tester.pumpAndSettle();

      final settings = AppSettings(db);
      await settings.load();
      expect(settings.reviewPerDay, 50);
      await drain(tester);
    });
  });

  group('the backup', () {
    testWidgets('a share that fails says so', (tester) async {
      channels.shareFails = true;
      await open(tester, find.text('Exportieren'));

      await tester.runAsync(() async {
        await tester.tap(find.text('Exportieren'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Exportieren').last);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(
        find.text('Die Sicherung hat nicht funktioniert.'),
        findsOneWidget,
      );
      await drain(tester);
    });

    testWidgets('a file that is not json at all says so', (tester) async {
      final file = File('${tmp.path}/kaputt.json')
        ..writeAsStringSync('nicht mal json');
      channels.pick = file.path;
      await open(tester, find.text('Importieren'));

      await tester.runAsync(() async {
        await tester.tap(find.text('Importieren'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text('Die Datei ist kein gültiges JSON.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a damaged section is named after the picker', (tester) async {
      // Section parse errors surface after picker dialog dismissal.
      final file = File('${tmp.path}/kaputt.json')
        ..writeAsStringSync(
          jsonEncode({
            'schema': backupSchema,
            'cards': [
              {'id': 'x'},
            ],
          }),
        );
      channels.pick = file.path;
      await open(tester, find.text('Importieren'));

      await tester.runAsync(() async {
        await tester.tap(find.text('Importieren'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Importieren').last);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      expect(find.text('Der Abschnitt cards ist beschädigt.'), findsOneWidget);
      expect(await db.select(db.cards).get(), isEmpty);
      await drain(tester);
    });

    testWidgets('without net the words are named as missing', (tester) async {
      final source = testDb();
      addTearDown(source.close);
      await cacheEntries(source, [
        sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      ]);
      await source
          .into(source.listItems)
          .insert(
            StoredListItem(listId: 'x', entryId: 1, addedAt: DateTime.now()),
          );

      final file = File('${tmp.path}/sicherung.json')
        ..writeAsStringSync(await exportBackup(source));
      channels.pick = file.path;
      stubApiFailure();

      await open(tester, find.text('Importieren'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Importieren'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Importieren').last);
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();

      expect(
        find.textContaining('sobald eine Internetverbindung besteht'),
        findsOneWidget,
      );
      await drain(tester);
    });
  });

  group('the offline link', () {
    testWidgets('says nothing is stored on an empty device', (tester) async {
      await open(tester, find.text('Gebärden herunterladen'));

      expect(find.text('Nichts gespeichert'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('counts the words and their size', (tester) async {
      for (final kind in AssetKind.values) {
        await db
            .into(db.assets)
            .insert(
              StoredAsset(
                videoId: sampleVideo.id,
                kind: kind,
                entryId: 1,
                localPath: '/tmp/951.${kind.name}',
                bytes: 1024 * 1024,
                downloadedAt: DateTime.now(),
              ),
            );
      }

      await open(tester, find.text('Gebärden herunterladen'));

      expect(find.text('1 Gebärde, 2.0 MB'), findsOneWidget);
      await drain(tester);
    });
  });

  group('a letter', () {
    testWidgets('shows what the server sends', (tester) async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Baum', 'currentVideo': sampleVideo.toJson()},
        ],
      });

      await tester.pumpWidget(
        await harness(db, LetterScreen(db: db, letter: 'B')),
      );
      await settle(tester);

      expect(find.widgetWithText(EntryRow, 'Baum'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('falls back to the cache when the request fails', (
      tester,
    ) async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Baum', currentVideo: sampleVideo),
      ]);
      stubApiFailure();

      await tester.pumpWidget(
        await harness(db, LetterScreen(db: db, letter: 'B')),
      );
      await settle(tester, steps: 20);

      expect(find.widgetWithText(EntryRow, 'Baum'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('says so when nothing is there', (tester) async {
      stubApi({'search': <Object>[]});

      await tester.pumpWidget(
        await harness(db, LetterScreen(db: db, letter: 'B')),
      );
      await settle(tester);

      expect(find.text('Nichts gefunden.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('hides entries without video', (tester) async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Baum'},
        ],
      });

      await tester.pumpWidget(
        await harness(db, LetterScreen(db: db, letter: 'B')),
      );
      await settle(tester);

      expect(find.widgetWithText(EntryRow, 'Baum'), findsNothing);
      await drain(tester);
    });

    testWidgets('shows them once that is switched on', (tester) async {
      final settings = AppSettings(db);
      await settings.load();
      await settings.set('showWithoutVideo', true);
      stubApi({
        'search': [
          {'id': 1, 'text': 'Baum'},
        ],
      });

      await tester.pumpWidget(
        await harness(db, LetterScreen(db: db, letter: 'B')),
      );
      await settle(tester);

      expect(find.widgetWithText(EntryRow, 'Baum'), findsOneWidget);
      await drain(tester);
    });
  });
}
