import 'dart:convert';

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

/// Tests download package UI controls requiring async isolate communication.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;

  setUpAll(() {
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

  Future<StoredPackage?> package(String id) =>
      (db.select(db.packages)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(await harness(db, OfflineScreen(db: db)));
    // Avoids infinite progress animation hangs.
    await settle(tester);
  }

  Future<void> hit(WidgetTester tester, Finder what) async {
    await tester.ensureVisible(what);
    await settle(tester, steps: 2);
    await tester.runAsync(() async {
      await tester.tap(what);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await settle(tester);
  }

  testWidgets('pausing stops the queue', (tester) async {
    await queue('entry:1', 'Hallo', PackageStatus.running);
    await open(tester);
    await hit(tester, find.byTooltip('Pausieren'));
    expect((await package('entry:1'))!.status, PackageStatus.paused);
    await drain(tester);
  });

  testWidgets('cancelling takes the row with it', (tester) async {
    await queue('entry:1', 'Hallo', PackageStatus.running);
    await open(tester);

    await hit(tester, find.byTooltip('Abbrechen'));

    expect(await package('entry:1'), isNull);
    await drain(tester);
  });
}
