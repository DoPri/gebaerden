import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/transfer/list_file.dart';
import 'package:gebaerden/ui/lists_screen.dart';

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
    tmp = Directory.systemTemp.createTempSync('sharing_test');
  });

  tearDown(() async {
    channels.remove();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<StoredList> seeded() async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Tschüss', currentVideo: sampleVideo),
    ]);
    final list = await createList(db, 'Begrüßung');
    await addToList(db, list.id, [1, 2]);
    return list;
  }

  testWidgets('sharing writes the file and hands it over', (tester) async {
    final list = await seeded();
    await tester.pumpWidget(await harness(db, ListScreen(db: db, id: list.id)));
    await tester.pumpAndSettle();

    // Writing the file is real io, which needs the real clock.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Liste teilen'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(channels.calls, contains('dev.fluttercommunity.plus/share.share'));
    await drain(tester);
  });

  testWidgets('renaming through the dialog sticks', (tester) async {
    final list = await seeded();
    await tester.pumpWidget(await harness(db, ListScreen(db: db, id: list.id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Liste umbenennen'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Küche');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(
      (await allLists(db)).firstWhere((l) => l.id == list.id).name,
      'Küche',
    );
    await drain(tester);
  });

  testWidgets('cancelling the rename changes nothing', (tester) async {
    final list = await seeded();
    await tester.pumpWidget(await harness(db, ListScreen(db: db, id: list.id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Liste umbenennen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Egal');
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(
      (await allLists(db)).firstWhere((l) => l.id == list.id).name,
      'Begrüßung',
    );
    await drain(tester);
  });

  testWidgets('deleting asks first and can be waved off', (tester) async {
    final list = await seeded();
    await tester.pumpWidget(await harness(db, ListScreen(db: db, id: list.id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Liste löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Liste löschen'), findsWidgets);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect((await allLists(db)).any((l) => l.id == list.id), isTrue);
    await drain(tester);
  });

  group('receiving a file', () {
    testWidgets('shows what is inside and takes it over', (tester) async {
      final list = await seeded();
      final text = await encodeList(db, list);
      final file = File('${tmp.path}/geteilt.dgsliste')
        ..writeAsStringSync(text);

      late BuildContext ctx;
      await tester.pumpWidget(
        await harness(
          db,
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Real file io never resolves under the test clock, so read it directly.
      unawaited(receiveListFile(ctx, db, file.readAsStringSync()));
      await tester.pumpAndSettle();

      expect(find.text('Begrüßung'), findsOneWidget);
      expect(find.textContaining('2 Wörter'), findsOneWidget);

      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      expect(
        (await allLists(db)).where((l) => l.name == 'Begrüßung'),
        hasLength(2),
      );
      await drain(tester);
    });

    testWidgets('a foreign file is refused with a reason', (tester) async {
      final file = File('${tmp.path}/fremd.dgsliste')
        ..writeAsStringSync('{"schema":"etwas-anderes"}');

      late BuildContext ctx;
      await tester.pumpWidget(
        await harness(
          db,
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Real file io never resolves under the test clock, so read it directly.
      unawaited(receiveListFile(ctx, db, file.readAsStringSync()));
      await tester.pumpAndSettle();

      expect(find.text('Das ist keine Gebärden-Liste.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a file that is not UTF-8 is refused with a reason', (
      tester,
    ) async {
      File('${tmp.path}/kaputt.dgsliste').writeAsBytesSync([0xFF, 0xFE]);

      late BuildContext ctx;
      await tester.pumpWidget(
        await harness(
          db,
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(
        () => openSharedPath(ctx, db, '${tmp.path}/kaputt.dgsliste'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Die Datei ist kein gültiges JSON.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a missing file is simply ignored', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        await harness(
          db,
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openSharedPath(ctx, db, '${tmp.path}/gibt-es-nicht.dgsliste');
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      await drain(tester);
    });

    testWidgets('waving the dialog off creates nothing', (tester) async {
      final list = await seeded();
      final text = await encodeList(db, list);
      final file = File('${tmp.path}/geteilt.dgsliste')
        ..writeAsStringSync(text);

      late BuildContext ctx;
      await tester.pumpWidget(
        await harness(
          db,
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Real file io never resolves under the test clock, so read it directly.
      unawaited(receiveListFile(ctx, db, file.readAsStringSync()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(
        (await allLists(db)).where((l) => l.name == 'Begrüßung'),
        hasLength(1),
      );
      await drain(tester);
    });
  });
}
