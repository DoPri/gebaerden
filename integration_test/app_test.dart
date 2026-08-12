import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/queries.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/media/variants.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/notify.dart';
import 'package:gebaerden/srs/charset.dart';
import 'package:gebaerden/topics.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a device against the live API:
///   flutter test integration_test
///
/// The app ships no dictionary of its own, so these check that signdict.org
/// still answers the way the app expects.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  testWidgets('a search reaches the dictionary and lands in the cache', (
    _,
  ) async {
    final rows = await cacheEntries(db, await searchWord('Haus'));
    expect(rows, isNotEmpty);
    expect(rows.any((r) => r.word.toLowerCase() == 'haus'), isTrue);
    expect(rows.any((r) => r.hasVideo), isTrue);
  });

  testWidgets('an entry carries its variants and a playable url', (_) async {
    final hits = await searchWord('Haus');
    final entry = await fetchEntry(
      hits.firstWhere((e) => e.text.toLowerCase() == 'haus').id,
    );

    expect(entry, isNotNull);
    expect(entry!.videos, isNotNull);
    expect(entry.currentVideo?.videoUrl, startsWith('http'));
  });

  testWidgets('the picked variant survives a round trip', (_) async {
    final hits = await searchWord('Haus');
    final full = await fetchEntry(
      hits.firstWhere((e) => e.text.toLowerCase() == 'haus').id,
    );
    final row = (await cacheEntries(db, [full!])).single;

    final other = row.videos!.last;
    await setPreferred(db, row.id, other);

    final again = await getEntry(db, row.id);
    expect((await preferredVideo(db, again!))!.id, other.id);
  });

  testWidgets('a topic resolves to real entries', (_) async {
    final list = await importTopic(db, topics.first);
    expect(list, isNotNull);
    expect(await listEntryIds(db, list!.id), isNotEmpty);
  });

  testWidgets('the alphabet resolves to handshapes with video', (_) async {
    final set = await loadCharset(db, Charset.alphabet);
    expect(set.length, greaterThan(20));
    expect(set.values.every((e) => e.hasVideo), isTrue);
    expect(set.keys, containsAll(['a', 'z']));
  });

  testWidgets('the letter index is complete enough to browse', (_) async {
    final page = await fetchIndexPage(1);
    expect(page, hasLength(pageSize));
  });

  /// Polls the row until the queue settles, the download is real.
  Future<StoredPackage> settled(String id, {int seconds = 120}) async {
    for (var i = 0; i < seconds * 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row != null &&
          const [
            PackageStatus.done,
            PackageStatus.error,
          ].contains(row.status)) {
        return row;
      }
    }
    fail('package $id never settled');
  }

  /// What the native side made of the tasks, for a failure message worth
  /// reading.
  Future<String> outcome(String id) async {
    final records = await FileDownloader().database.allRecords(group: id);
    return records
        .map((r) => '${r.taskId} ${r.status.name} ${r.exception ?? ''}')
        .join('\n');
  }

  group('the downloader', () {
    late Downloads manager;

    setUp(() async {
      // Same order as main(). start() posts into the shade at once, and an
      // uninitialized plugin answers that with a NullPointerException.
      await initNotifications();
      manager = Downloads(db);
      downloads = manager;
      // The update stream takes one listener and every start() adds one.
      await FileDownloader().resetUpdates();
      await FileDownloader().database.deleteAllRecords();
      // forTesting() is a real file on the device and outlives the run.
      await db.delete(db.assets).go();
      await db.delete(db.packages).go();
      await manager.start();
    });

    tearDown(() async {
      await manager.dispose();
      await FileDownloader().database.deleteAllRecords();
    });

    testWidgets('a package lands on disk and the counters add up', (_) async {
      final hits = await searchWord('Haus');
      final entry = hits.firstWhere(
        (e) =>
            e.text.toLowerCase() == 'haus' && e.currentVideo?.videoUrl != null,
      );
      await cacheEntries(db, [entry]);

      await manager.startPackage(EntryPackage(entry.id, entry.text));
      final row = await settled('entry:${entry.id}');

      expect(row.status, PackageStatus.done, reason: await outcome(row.id));
      // One video and one thumbnail. The denominator is the plan, it used to
      // count the records and climbed while the queue was still filling.
      expect(row.total, 2);
      expect(row.done, greaterThan(0));
      expect(row.done, lessThanOrEqualTo(row.total));

      final assets = await db.select(db.assets).get();
      expect(assets, isNotEmpty);
      for (final asset in assets) {
        expect(File(asset.localPath).existsSync(), isTrue);
        expect(asset.bytes, greaterThan(0));
        expect(File(asset.localPath).lengthSync(), asset.bytes);
      }
      // Counted from the records of this run, so at most what is on disk.
      final onDisk = assets.fold<int>(0, (sum, a) => sum + a.bytes);
      expect(row.bytes, greaterThan(0));
      expect(row.bytes, lessThanOrEqualTo(onDisk));

      await manager.removeDownloads([entry.id]);
    });

    testWidgets('a second run only fetches what is missing', (_) async {
      final hits = await searchWord('Haus');
      final entry = hits.firstWhere(
        (e) =>
            e.text.toLowerCase() == 'haus' && e.currentVideo?.videoUrl != null,
      );
      await cacheEntries(db, [entry]);
      final id = 'entry:${entry.id}';

      await manager.startPackage(EntryPackage(entry.id, entry.text));
      final first = await settled(id);
      expect(first.done, greaterThan(0));

      // What arrived is on disk now, so the second run plans only what is
      // still missing and must not count the run before it. A file that is
      // gone upstream stays missing, so the plan may not be empty.
      await manager.startPackage(EntryPackage(entry.id, entry.text));
      final second = await settled(id);
      expect(second.total, lessThan(first.total));
      expect(second.done, lessThanOrEqualTo(second.total));

      await manager.removeDownloads([entry.id]);
    });

    testWidgets('pausing stops the queue and resuming finishes it', (_) async {
      final entries = await searchLetter('Q');
      await cacheEntries(db, entries);
      final id = 'letter:Q';

      await manager.startPackage(const LetterPackage('Q'));
      await manager.pausePackage(id);

      var row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.status, PackageStatus.paused);

      // The cancels the pause triggers arrive after it. The row has to stay
      // put through them instead of flipping to done.
      await Future<void>.delayed(const Duration(seconds: 3));
      row = await (db.select(
        db.packages,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.status, PackageStatus.paused);

      await manager.resumePackage(row);
      final finished = await settled(id);
      expect(finished.status, isNot(PackageStatus.running));

      // What the pause interrupted has to be on disk after the resume. Single
      // files are gone upstream, the clips are what counts.
      final videos = (await db.select(db.assets).get()).where(
        (a) => a.kind == AssetKind.video,
      );
      expect(videos, isNotEmpty, reason: await outcome(id));
      for (final asset in videos) {
        expect(File(asset.localPath).existsSync(), isTrue);
      }

      await manager.cancelPackage(id);
      expect(
        await (db.select(db.packages)..where((t) => t.id.equals(id))).get(),
        isEmpty,
      );
    });
  });

  testWidgets('the reminder can be scheduled and taken back', (_) async {
    await initNotifications();

    // Needs the notification permission, which the runner grants beforehand.
    final ok = await scheduleReminders(const [
      (
        reminder: Reminder(days: {1, 2, 3, 4, 5}, hour: 19, minute: 30),
        listId: 'kueche',
        due: 5,
      ),
    ]);
    expect(ok, isTrue, reason: 'without the permission this fails');

    // Five days, so five alarms.
    final pending = await pendingReminders();
    expect(pending, hasLength(5));
    expect(pending.first.body, contains('5'));

    await cancelReminders();
    expect(await pendingReminders(), isEmpty);
  });
}
