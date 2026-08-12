import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/ui/offline_screen.dart';
import 'package:http/http.dart' as http;

import 'channels.dart';
import 'fake_storage.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;

  setUpAll(() {
    // Must happen before anything touches the singleton.
    FileDownloader(persistentStorage: MemoryStorage());
  });

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
    downloads = Downloads(db);
  });

  tearDown(() async {
    useClient(http.Client());
    await FileDownloader().database.deleteAllRecords();
    channels.remove();
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(await harness(db, OfflineScreen(db: db)));
    // A running package animates forever, so never pumpAndSettle here.
    await settle(tester);
  }

  /// Rows can sit below the fold, and a tap on those goes nowhere.
  Future<void> hit(WidgetTester tester, Finder what) async {
    await tester.ensureVisible(what);
    await settle(tester, steps: 2);
    await tester.tap(what);
    await settle(tester);
  }

  Future<StoredPackage?> package(String id) =>
      (db.select(db.packages)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> queue(String id, String label, PackageStatus status) => db
      .into(db.packages)
      .insertOnConflictUpdate(
        StoredPackage(
          id: id,
          label: label,
          spec: jsonEncode(const EntryPackage(1, 'Hallo').toJson()),
          status: status,
          done: 1,
          total: 4,
          bytes: 12,
          updatedAt: DateTime.now(),
        ),
      );

  group('starting a package', () {
    testWidgets('the whole dictionary', (tester) async {
      stubApi({'index': <Object>[]});
      await open(tester);

      await hit(tester, find.text('Alle Gebärden'));

      expect(await package('all'), isNotNull);
      await drain(tester);
    });

    testWidgets('a single letter', (tester) async {
      stubApi({'search': <Object>[]});
      await open(tester);

      await hit(tester, find.text('B'));

      expect(await package('letter:B'), isNotNull);
      await drain(tester);
    });
  });

  testWidgets('clearing throws the files and the rows out', (tester) async {
    final dir = Directory('${channels.tempDir.path}/media')
      ..createSync(recursive: true);
    final file = File('${dir.path}/951.mp4')..writeAsStringSync('x');
    await db
        .into(db.assets)
        .insert(
          StoredAsset(
            videoId: 951,
            kind: AssetKind.video,
            entryId: 1,
            localPath: file.path,
            bytes: 5,
            downloadedAt: DateTime.now(),
          ),
        );
    await queue('entry:1', 'Hallo', PackageStatus.done);

    await open(tester);
    await hit(tester, find.text('Leeren'));

    expect(file.existsSync(), isFalse);
    expect(await db.select(db.assets).get(), isEmpty);
    expect(await db.select(db.packages).get(), isEmpty);
    await drain(tester);
  });
}
