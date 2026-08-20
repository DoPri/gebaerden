import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/theme.dart';
import 'package:gebaerden/topics.dart';

import 'channels.dart';
import 'fake_storage.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;

  setUpAll(() {
    // Required before accessing FileDownloader singleton.
    FileDownloader(persistentStorage: MemoryStorage());
  });

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
  });

  tearDown(() async {
    channels.remove();
    await db.close();
  });

  // Reminder plugin requires dart:io platform implementation not testable on host.

  group('network status', () {
    test('starts from what the platform reports', () async {
      final status = NetworkStatus();
      await status.start();
      expect(status.online, isTrue);
      status.dispose();
    });

    test('announces a change only when it flips', () async {
      final status = NetworkStatus();
      await status.start();

      var calls = 0;
      status.addListener(() => calls++);
      status.goOffline();
      expect(calls, 1);
      expect(status.online, isFalse);
      status.dispose();
    });
  });

  group('downloads', () {
    test('one entry becomes a video and a thumbnail task', () async {
      final rows = await cacheEntries(db, [
        sampleEntry(currentVideo: sampleVideo),
      ]);
      downloads = Downloads(db);

      await downloads.startPackage(EntryPackage(rows.single.id, 'Zug'));

      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('entry:835'))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.total, 2);
      expect(row.status, PackageStatus.running);
    });

    test('an entry without video makes no tasks and lands as done', () async {
      final rows = await cacheEntries(db, [sampleEntry(id: 9, text: 'Leer')]);
      downloads = Downloads(db);

      await downloads.startPackage(EntryPackage(rows.single.id, 'Leer'));

      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('entry:9'))).getSingle();
      expect(row.total, 0);
      expect(row.status, PackageStatus.done);
    });

    test('what is already on disk is not fetched again', () async {
      final rows = await cacheEntries(db, [
        sampleEntry(currentVideo: sampleVideo),
      ]);
      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: sampleVideo.id,
              kind: AssetKind.video,
              entryId: rows.single.id,
              localPath: '/tmp/egal.mp4',
              bytes: 1,
              downloadedAt: DateTime.now(),
            ),
          );

      downloads = Downloads(db);
      await downloads.startPackage(EntryPackage(rows.single.id, 'Zug'));

      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('entry:835'))).getSingle();
      expect(row.total, 1);
    });

    test('a list package walks the list', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'A', currentVideo: sampleVideo),
        sampleEntry(id: 2, text: 'B', currentVideo: sampleVideo),
      ]);
      final list = await createList(db, 'Küche');
      await addToList(db, list.id, [1, 2]);

      downloads = Downloads(db);
      await downloads.startPackage(ListPackage(list.id, 'Küche'));

      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('list:${list.id}'))).getSingle();
      expect(row.total, 4);
      expect(row.label, 'Küche');
    });

    test('pausing marks the row, cancelling drops it', () async {
      final rows = await cacheEntries(db, [
        sampleEntry(currentVideo: sampleVideo),
      ]);
      downloads = Downloads(db);
      await downloads.startPackage(EntryPackage(rows.single.id, 'Zug'));

      await downloads.pausePackage('entry:835');
      var row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('entry:835'))).getSingle();
      expect(row.status, PackageStatus.paused);

      await downloads.resumePackage(row);
      row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('entry:835'))).getSingle();
      expect(row.status, isNot(PackageStatus.paused));

      await downloads.cancelPackage('entry:835');
      expect(
        await (db.select(
          db.packages,
        )..where((t) => t.id.equals('entry:835'))).getSingleOrNull(),
        isNull,
      );
    });

    test('removing takes the rows with the files', () async {
      await cacheEntries(db, [sampleEntry(currentVideo: sampleVideo)]);
      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: sampleVideo.id,
              kind: AssetKind.video,
              entryId: 835,
              localPath: '/tmp/gibt-es-nicht.mp4',
              bytes: 1,
              downloadedAt: DateTime.now(),
            ),
          );

      downloads = Downloads(db);
      expect(await downloads.isDownloaded(835), isTrue);

      await downloads.removeDownloads([835]);
      expect(await downloads.isDownloaded(835), isFalse);
    });

    test('a row whose file vanished is cleaned up on reconcile', () async {
      await cacheEntries(db, [sampleEntry(currentVideo: sampleVideo)]);
      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: sampleVideo.id,
              kind: AssetKind.video,
              entryId: 835,
              localPath: '/tmp/weg-${DateTime.now().microsecond}.mp4',
              bytes: 1,
              downloadedAt: DateTime.now(),
            ),
          );

      downloads = Downloads(db);
      await downloads.reconcile();

      expect(await db.select(db.assets).get(), isEmpty);
    });

    test('a run left over from a kill goes back in the queue', () async {
      await db
          .into(db.packages)
          .insert(
            StoredPackage(
              id: 'all',
              label: 'Alle Gebärden',
              spec: '{"kind":"all"}',
              status: PackageStatus.running,
              done: 3,
              total: 10,
              bytes: 0,
              updatedAt: DateTime.now(),
            ),
          );

      downloads = Downloads(db);
      await downloads.reconcile();

      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('all'))).getSingle();
      expect(row.status, PackageStatus.queued);
    });
  });

  group('more downloads', () {
    test('a letter package resolves through the live search', () async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Baum', 'currentVideo': sampleVideo.toJson()},
          {'id': 2, 'text': 'Zug', 'currentVideo': sampleVideo.toJson()},
        ],
      });
      downloads = Downloads(db);
      await downloads.startPackage(const LetterPackage('B'));

      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('letter:B'))).getSingle();
      expect(row.total, 2);
    });

    test('a failing resolve lands as an error with a reason', () async {
      stubApiFailure();
      downloads = Downloads(db);
      await downloads.startPackage(const LetterPackage('B'));

      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('letter:B'))).getSingle();
      expect(row.status, PackageStatus.error);
      expect(row.error, isNotNull);
    });

    test('the whole dictionary walks every index page', () async {
      var page = 0;
      stubApi({});
      stubPer((_) {
        page++;
        return {
          'index': page <= 2
              ? [
                  {
                    'id': page,
                    'text': 'Wort $page',
                    'currentVideo': sampleVideo.toJson(),
                  },
                ]
              : <Object>[],
        };
      });

      downloads = Downloads(db);
      await downloads.startPackage(const AllPackage());

      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals('all'))).getSingle();
      expect(row.total, 4);
      expect(row.label, 'Alle Gebärden');
    });

    test('changing the variant refetches an entry that is offline', () async {
      final rows = await cacheEntries(db, [
        sampleEntry(currentVideo: sampleVideo),
      ]);
      downloads = Downloads(db);

      await refreshDownloadFor(db, rows.single.id);
      expect(
        await (db.select(
          db.packages,
        )..where((t) => t.id.equals('entry:835'))).getSingleOrNull(),
        isNull,
      );

      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: sampleVideo.id,
              kind: AssetKind.video,
              entryId: rows.single.id,
              localPath: '/tmp/da.mp4',
              bytes: 1,
              downloadedAt: DateTime.now(),
            ),
          );

      await refreshDownloadFor(db, rows.single.id);
      expect(
        await (db.select(
          db.packages,
        )..where((t) => t.id.equals('entry:835'))).getSingleOrNull(),
        isNotNull,
      );
    });

    test('an unknown entry is simply skipped', () async {
      downloads = Downloads(db);
      await refreshDownloadFor(db, 999);
      expect(await db.select(db.packages).get(), isEmpty);
    });
  });

  group('topics', () {
    test('resolves the words and builds a list', () async {
      final topic = topics.first;
      stubApi({
        for (final (i, _) in topic.words.indexed)
          'w$i': [
            {'id': 100 + i, 'text': topic.words[i]},
          ],
        for (final (i, _) in topic.words.indexed)
          'e$i': {
            'id': 100 + i,
            'text': topic.words[i],
            'currentVideo': sampleVideo.toJson(),
          },
      });

      final list = await importTopic(db, topic);
      expect(list, isNotNull);
      expect(list!.name, topic.name);
      expect(await listEntryIds(db, list.id), hasLength(topic.words.length));
    });

    test('nothing found means no list', () async {
      stubApi({});
      expect(await importTopic(db, topics.first), isNull);
    });
  });

  group('colors', () {
    test('copyWith replaces only what it is given', () {
      const swapped = Color(0xFF123456);
      final next = AppColors.light.copyWith(accent: swapped);
      expect(next.accent, swapped);
      expect(next.bg, AppColors.light.bg);
    });

    test('lerp walks from one theme to the other', () {
      final half = AppColors.light.lerp(AppColors.dark, 1);
      expect(half.bg, AppColors.dark.bg);

      final none = AppColors.light.lerp(null, 0.5);
      expect(none, same(AppColors.light));
    });
  });
}
