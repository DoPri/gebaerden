import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/transfer/backup.dart';
import 'package:gebaerden/ui/more_screen.dart';
import 'package:http/http.dart' as http;

import 'channels.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late Directory tmp;

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
    tmp = Directory.systemTemp.createTempSync('backup_ui_test');
  });

  tearDown(() async {
    useClient(http.Client());
    channels.remove();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Exportieren'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('exporting hands a file to the share sheet', (tester) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    final card = await getOrCreateCard(db, 1, Direction.recognition);
    await gradeCard(db, card, f.Rating.good);

    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Exportieren'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    // Targets modal dialog button over matching screen button.
    await tester.runAsync(() async {
      await tester.tap(find.text('Exportieren').last);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(channels.calls, contains('dev.fluttercommunity.plus/share.share'));
    await drain(tester);
  });

  testWidgets('backing out of the picker changes nothing', (tester) async {
    channels.pick = null;
    await open(tester);

    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();

    expect(await db.select(db.cards).get(), isEmpty);
    await drain(tester);
  });

  testWidgets('importing a file reports what came in', (tester) async {
    final source = testDb();
    addTearDown(source.close);
    await cacheEntries(source, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    final card = await getOrCreateCard(source, 1, Direction.recognition);
    await gradeCard(source, card, f.Rating.good);
    await createList(source, 'Küche');

    final file = File('${tmp.path}/sicherung.json')
      ..writeAsStringSync(await exportBackup(source));
    channels.pick = file.path;
    stubPer(
      (_) => {
        'e0': {'id': 1, 'text': 'Hallo', 'currentVideo': sampleVideo.toJson()},
      },
    );

    await open(tester);
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

    expect(
      find.textContaining('1 Karte, 1 Antwort und 1 Liste importiert.'),
      findsOneWidget,
    );
    expect(find.textContaining('1 Wort importiert.'), findsOneWidget);
    expect((await db.select(db.cards).get()).single.entryId, 1);
    expect((await allLists(db)).map((l) => l.name), contains('Küche'));
    await drain(tester);
  });

  testWidgets('a foreign file is refused with a reason', (tester) async {
    final file = File('${tmp.path}/fremd.json')
      ..writeAsStringSync('{"schema":"etwas-anderes"}');
    channels.pick = file.path;

    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Importieren'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Das ist keine Sicherung dieser App.'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a section left unticked is not imported', (tester) async {
    final source = testDb();
    addTearDown(source.close);
    await cacheEntries(source, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    await gradeCard(
      source,
      await getOrCreateCard(source, 1, Direction.recognition),
      f.Rating.good,
    );
    await createList(source, 'Küche');

    final file = File('${tmp.path}/sicherung.json')
      ..writeAsStringSync(await exportBackup(source));
    channels.pick = file.path;

    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Importieren'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lernstand und Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listen und Wörter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listen und Wörter'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Importieren').last);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(await db.select(db.cards).get(), isEmpty);
    expect((await allLists(db)).map((l) => l.name), contains('Küche'));
    await drain(tester);
  });

  testWidgets('backing out of the section picker changes nothing', (
    tester,
  ) async {
    final source = testDb();
    addTearDown(source.close);
    await createList(source, 'Küche');

    final file = File('${tmp.path}/sicherung.json')
      ..writeAsStringSync(await exportBackup(source));
    channels.pick = file.path;

    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Importieren'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect((await allLists(db)).map((l) => l.name), isNot(contains('Küche')));
    await drain(tester);
  });

  testWidgets('the picked mode reaches the import', (tester) async {
    final source = testDb();
    addTearDown(source.close);
    await cacheEntries(source, [
      sampleEntry(id: 2, text: 'Tschüss', currentVideo: sampleVideo),
    ]);
    await gradeCard(
      source,
      await getOrCreateCard(source, 2, Direction.recognition),
      f.Rating.good,
    );

    // Pre-populates cache to avoid network requests during import.
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Tschüss', currentVideo: sampleVideo),
    ]);
    await gradeCard(
      db,
      await getOrCreateCard(db, 1, Direction.recognition),
      f.Rating.good,
    );

    final file = File('${tmp.path}/sicherung.json')
      ..writeAsStringSync(await exportBackup(source));
    channels.pick = file.path;

    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Importieren'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ersetzen'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Importieren').last);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect((await db.select(db.cards).get()).map((c) => c.entryId), [2]);
    await drain(tester);
  });
}
