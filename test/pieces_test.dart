import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/api/queries.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/media/media.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/search/offline.dart';
import 'package:gebaerden/transfer/backup.dart';
import 'package:gebaerden/transfer/list_file.dart';
import 'package:gebaerden/ui/widgets/entry_list.dart';
import 'package:gebaerden/ui/widgets/list_picker.dart';
import 'package:gebaerden/ui/widgets/pieces.dart';
import 'package:http/http.dart' as http;

import 'channels.dart';
import 'fake_storage.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late Directory tmp;

  setUpAll(() {
    // Must happen before anything touches the singleton.
    FileDownloader(persistentStorage: MemoryStorage());
  });

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
    downloads = Downloads(db);
    tmp = Directory.systemTemp.createTempSync('pieces_test');
  });

  tearDown(() async {
    useClient(http.Client());
    channels.remove();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  group('the errors say what went wrong', () {
    test('a broken list file', () {
      expect(ListFileError('kaputt').toString(), 'kaputt');
      expect(
        () => parseListFile('"nur ein string"'),
        throwsA(
          isA<ListFileError>().having(
            (e) => e.message,
            'message',
            contains('unerwarteten Aufbau'),
          ),
        ),
      );
      expect(
        () => parseListFile('{"schema":"$listSchema","name":"x"}'),
        throwsA(
          isA<ListFileError>().having(
            (e) => e.message,
            'message',
            contains('unvollständig'),
          ),
        ),
      );
    });

    test('a broken backup', () {
      expect(BackupError('broken').toString(), 'broken');
    });

    test('the api', () {
      expect(
        GraphqlError(['too much', 'too little']).toString(),
        'GraphqlError: too much; too little',
      );
      expect(ApiError('gone').toString(), contains('gone'));
    });
  });

  test('an answer without data is refused', () async {
    useClient(_FixedClient('{"noData":1}'));
    await expectLater(searchWord('Haus'), throwsA(isA<ApiError>()));
  });

  test('more requests than slots still all get through', () async {
    var served = 0;
    useClient(_CountingClient(() => served++));

    await Future.wait<void>([
      for (var i = 0; i < 8; i++) searchWord('Haus $i'),
    ]);
    expect(served, 8);
  });

  test('a shared list without the net keeps what it knows', () async {
    stubApiFailure();
    final list = await importSharedList(
      db,
      const SharedList('Bad', [(id: 1, word: 'Hallo')]),
    );
    expect(list.name, 'Bad');
  });

  group('the offline search', () {
    test('sorts shorter words before longer ones', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Hausboot', currentVideo: sampleVideo),
        sampleEntry(id: 2, text: 'Haus', currentVideo: sampleVideo),
        sampleEntry(id: 3, text: 'Hausbau', currentVideo: sampleVideo),
      ]);
      invalidateIndex();
      final hits = await offlineSearch(db, 'haus');
      expect(hits.map((e) => e.word).take(2), ['Haus', 'Hausbau']);
    });

    test('sorts alphabetically at the same length', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Bär', currentVideo: sampleVideo),
        sampleEntry(id: 2, text: 'Bar', currentVideo: sampleVideo),
      ]);
      invalidateIndex();
      final hits = await offlineSearch(db, 'ba');
      expect(hits.map((e) => e.word), ['Bar', 'Bär']);
    });
  });

  test('a stored thumbnail wins over the url', () async {
    final file = File('${tmp.path}/951.jpg')..writeAsBytesSync(onePixelPng);
    final rows = await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    await db
        .into(db.assets)
        .insert(
          StoredAsset(
            videoId: sampleVideo.id,
            kind: AssetKind.thumbnail,
            entryId: 1,
            localPath: file.path,
            bytes: 1,
            downloadedAt: DateTime.now(),
          ),
        );

    final sources = await thumbnailsFor(db, rows);
    expect(sources[1]!.isFile, isTrue);
  });

  test('a change in the connection is passed on', () async {
    final status = NetworkStatus();
    var notified = 0;
    status.addListener(() => notified++);
    await status.start();

    channels.reportConnectivity(['none']);
    await Future<void>.delayed(Duration.zero);
    expect(status.online, isFalse);
    expect(notified, 1);

    channels.reportConnectivity(['wifi']);
    await Future<void>.delayed(Duration.zero);
    expect(status.online, isTrue);
    expect(notified, 2);

    // The same state again says nothing.
    channels.reportConnectivity(['mobile']);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 2);
    status.dispose();
  });

  testWidgets('a link opens outside the app', (tester) async {
    await tester.pumpWidget(
      await harness(
        db,
        const LinkText(label: 'signdict.org', url: 'https://signdict.org'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('signdict.org'));
    await tester.pumpAndSettle();

    expect(channels.calls, contains('plugins.flutter.io/url_launcher.launch'));
    await drain(tester);
  });

  testWidgets('a list can carry a header row', (tester) async {
    final rows = await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);

    await tester.pumpWidget(
      await harness(
        db,
        EntryListView(
          db: db,
          entries: rows,
          onOpen: (_) {},
          header: const Text('Kopfzeile'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kopfzeile'), findsOneWidget);
    expect(find.widgetWithText(EntryRow, 'Hallo'), findsOneWidget);
    await drain(tester);
  });

  group('the offline switch on an entry', () {
    testWidgets('saves the sign', (tester) async {
      final rows = await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      ]);

      await tester.pumpWidget(
        await harness(db, OfflineToggle(db: db, entry: rows.single)),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Offline speichern'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await settle(tester);

      expect(channels.enqueued, contains('951-video'));
      await drain(tester);
    });

    testWidgets('and drops it again', (tester) async {
      final file = File('${tmp.path}/951.mp4')..writeAsStringSync('x');
      final rows = await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      ]);
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

      await tester.pumpWidget(
        await harness(db, OfflineToggle(db: db, entry: rows.single)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Offline gespeichert'));
      await settle(tester);

      expect(await db.select(db.assets).get(), isEmpty);
      expect(file.existsSync(), isFalse);
      await drain(tester);
    });
  });
}

/// Answers every request with the same body.
class _FixedClient extends http.BaseClient {
  _FixedClient(this.body);

  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(body.codeUnits),
        200,
        headers: {'content-type': 'application/json'},
      );
}

/// Counts how many requests actually went out.
class _CountingClient extends http.BaseClient {
  _CountingClient(this.onSend);

  final void Function() onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onSend();
    return http.StreamedResponse(
      Stream.value('{"data":{"search":[]}}'.codeUnits),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
