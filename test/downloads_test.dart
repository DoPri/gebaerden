import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/notify.dart';

import 'channels.dart';
import 'fake_storage.dart';
import 'support.dart';

/// Pretends the native side reported back, which is the only way into the
/// update stream the manager listens on.
Future<void> report(Task task, TaskStatus status) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'com.bbflight.background_downloader.background',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('statusUpdate', [jsonEncode(task.toJson()), status.index]),
        ),
        (_) {},
      );
}

DownloadTask videoTask({
  int videoId = 951,
  int entryId = 1,
  String group = 'entry:1',
  AssetKind kind = AssetKind.video,
}) => DownloadTask(
  taskId: '$videoId-${kind.name}',
  url: 'https://example.invalid/$videoId',
  filename: kind == AssetKind.video ? '$videoId.mp4' : '$videoId.jpg',
  directory: 'media',
  baseDirectory: BaseDirectory.applicationSupport,
  group: group,
  updates: Updates.statusAndProgress,
  metaData: jsonEncode({
    'videoId': videoId,
    'kind': kind.name,
    'entryId': entryId,
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late Downloads manager;
  late MemoryStorage storage;

  setUpAll(() {
    // Must happen before anything touches the singleton.
    storage = MemoryStorage();
    FileDownloader(persistentStorage: storage);
  });

  setUp(() async {
    db = testDb();
    channels = FakeChannels()..install();
    // The update stream takes one listener and every start() adds one.
    await FileDownloader().resetUpdates();
    manager = Downloads(db);
    downloads = manager;
  });

  tearDown(() async {
    await manager.dispose();
    await FileDownloader().database.deleteAllRecords();
    channels.remove();
    await db.close();
  });

  /// The file the downloader would have written.
  Future<File> lay(Task task, {int bytes = 40}) async {
    final file = File(await task.filePath());
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0));
    return file;
  }

  Future<void> queue(String id, String label, PackageStatus status) => db
      .into(db.packages)
      .insertOnConflictUpdate(
        StoredPackage(
          id: id,
          label: label,
          spec: jsonEncode(const EntryPackage(1, 'Hallo').toJson()),
          status: status,
          done: 0,
          total: 2,
          bytes: 0,
          updatedAt: DateTime.now(),
        ),
      );

  Future<StoredPackage> package(String id) =>
      (db.select(db.packages)..where((t) => t.id.equals(id))).getSingle();

  group('starting up', () {
    test('catches up on what the native side finished meanwhile', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      final task = videoTask();
      await lay(task, bytes: 32);
      await FileDownloader().database.updateRecord(
        TaskRecord(task, TaskStatus.complete, 1, 32),
      );

      await manager.start();
      expect((await db.select(db.assets).get()).single.bytes, 32);
    });

    test('a package left on running goes back in the queue', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();
      expect((await package('entry:1')).status, PackageStatus.queued);
    });

    test('the shade says what the row says', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // The label and the counts of the row, not the downloader's own tally
      // of the tasks it has been handed so far.
      final last = channels.shown.last;
      expect(last['title'], 'Hallo');
      expect(last['body'], '0 von 2');
    });

    test('a package that is gone takes its notification with it', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final id = channels.shown.last['id'];

      await manager.cancelPackage('entry:1');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(channels.cancelled, contains(id));
    });

    test('the queue is told to run in the foreground', () async {
      // Without it Android ends a task after nine minutes.
      await manager.start();
      expect(
        channels.calls,
        contains('com.bbflight.background_downloader.configForegroundFileSize'),
      );
    });

    test('a task of a package that is not running stays gone', () async {
      await queue('entry:1', 'Hallo', PackageStatus.paused);
      // Stopping deletes the records, but the app does not always live long
      // enough to finish that. What is left must not restart the download.
      await FileDownloader().database.updateRecord(
        TaskRecord(videoTask(videoId: 7777), TaskStatus.enqueued, 0, 0),
      );

      await manager.start();
      expect(channels.enqueued, isNot(contains('7777-video')));
      expect((await package('entry:1')).status, PackageStatus.paused);
    });

    test('a task killed with the app is enqueued again', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      // All a kill leaves behind. The native queue is empty and no file was
      // written, so tracking cannot mark the record complete either.
      await FileDownloader().database.updateRecord(
        TaskRecord(videoTask(videoId: 7777), TaskStatus.enqueued, 0, 0),
      );

      await manager.start();
      expect(channels.enqueued, contains('7777-video'));
      expect((await package('entry:1')).status, PackageStatus.running);
    });
  });

  group('an update from the native side', () {
    test('a finished file lands in the assets', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      final task = videoTask();
      await lay(task, bytes: 128);
      await report(task, TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final asset = (await db.select(db.assets).get()).single;
      expect(asset.videoId, 951);
      expect(asset.entryId, 1);
      expect(asset.kind, AssetKind.video);
      expect(asset.bytes, 128);
    });

    test('the counters on the package follow', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      final video = videoTask();
      final thumb = videoTask(kind: AssetKind.thumbnail);
      await lay(video, bytes: 100);
      await lay(thumb, bytes: 20);
      await report(video, TaskStatus.complete);
      await report(thumb, TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final row = await package('entry:1');
      expect(row.done, 2);
      expect(row.total, 2);
      expect(row.bytes, 120);
      expect(row.status, PackageStatus.done);
    });

    test('a package that got nothing is an error', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      await report(videoTask(), TaskStatus.failed);
      await report(videoTask(kind: AssetKind.thumbnail), TaskStatus.failed);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect((await package('entry:1')).status, PackageStatus.error);
    });

    test('one lost file does not sink the package', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      final video = videoTask();
      await lay(video, bytes: 64);
      await report(video, TaskStatus.complete);
      // Thumbnails are gone upstream often enough. The package still counts.
      await report(videoTask(kind: AssetKind.thumbnail), TaskStatus.failed);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final row = await package('entry:1');
      expect(row.status, PackageStatus.done);
      expect(row.done, 1);
      expect(row.error, contains('1'));
    });

    test('a package is not done before its plan has reported', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      // One of two files reported. Early in a big package every record the
      // native side knows can be complete at once, which used to read as done.
      final video = videoTask();
      await lay(video);
      await report(video, TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final row = await package('entry:1');
      expect(row.status, PackageStatus.running);
      expect(row.done, 1);
      expect(row.total, 2);
    });

    test('a file that never arrived is not recorded', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      await report(videoTask(videoId: 4242), TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(await db.select(db.assets).get(), isEmpty);
    });

    test('an update for a package nobody knows is dropped', () async {
      await manager.start();

      final task = videoTask(group: 'letter:Z');
      await lay(task);
      await report(task, TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(await db.select(db.packages).get(), isEmpty);
      expect(await db.select(db.assets).get(), hasLength(1));
    });

    test('many updates are counted once', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      final task = videoTask();
      await lay(task);
      for (var i = 0; i < 5; i++) {
        await report(task, TaskStatus.running);
      }
      await report(task, TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect((await package('entry:1')).done, 1);
    });

    test('a task the system paused goes back into the queue', () async {
      // Nobody here asks for a pause. The system does and then it waits.
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      final task = videoTask();
      await storage.storeResumeData(ResumeData(task, 'weiter', 20));
      addTearDown(() => storage.removeResumeData(null));
      await report(task, TaskStatus.paused);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(channels.enqueued, contains(task.taskId));
    });

    test('a package that was only cancelled is not done', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      // Both files of the plan came back cancelled and nothing arrived, so a
      // resume still has everything to fetch.
      await report(videoTask(), TaskStatus.canceled);
      await report(videoTask(kind: AssetKind.thumbnail), TaskStatus.canceled);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // start() put the row left on running back in the queue and the cancels
      // must not carry it from there to done.
      expect((await package('entry:1')).status, PackageStatus.queued);
      expect((await package('entry:1')).done, 0);
    });

    test('a paused package survives the cancels that follow', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      await manager.pausePackage('entry:1');
      // The plugin reports every canceled task and the records stay.
      await report(videoTask(), TaskStatus.canceled);
      await report(videoTask(kind: AssetKind.thumbnail), TaskStatus.canceled);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect((await package('entry:1')).status, PackageStatus.paused);
    });
  });

  group('catching up after the app was gone', () {
    test('finished tasks the app missed are written', () async {
      final task = videoTask();
      await lay(task, bytes: 64);
      await FileDownloader().database.updateRecord(
        TaskRecord(task, TaskStatus.complete, 1, 64),
      );

      await manager.reconcile();
      expect((await db.select(db.assets).get()).single.bytes, 64);
    });

    test('what is already known is left alone', () async {
      final task = videoTask();
      await lay(task);
      await FileDownloader().database.updateRecord(
        TaskRecord(task, TaskStatus.complete, 1, 40),
      );
      await manager.reconcile();

      final first = (await db.select(db.assets).get()).single;
      await manager.reconcile();
      expect((await db.select(db.assets).get()).single, first);
    });

    test('a row without its file goes', () async {
      final task = videoTask();
      final file = await lay(task);
      await FileDownloader().database.updateRecord(
        TaskRecord(task, TaskStatus.complete, 1, 40),
      );
      await manager.reconcile();

      file.deleteSync();
      await manager.reconcile();
      expect(await db.select(db.assets).get(), isEmpty);
    });

    test('an unfinished task keeps the package on running', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await FileDownloader().database.updateRecord(
        TaskRecord(videoTask(), TaskStatus.running, 0.5, 0),
      );

      await manager.reconcile();
      expect((await package('entry:1')).status, PackageStatus.running);
    });

    test('one package that finished does not park another', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await queue('entry:2', 'Tschüss', PackageStatus.running);
      await FileDownloader().database.updateRecord(
        TaskRecord(videoTask(), TaskStatus.complete, 1, 40),
      );
      await FileDownloader().database.updateRecord(
        TaskRecord(
          videoTask(videoId: 8888, entryId: 2, group: 'entry:2'),
          TaskStatus.running,
          0.5,
          0,
        ),
      );

      await manager.reconcile();
      expect((await package('entry:1')).status, PackageStatus.queued);
      expect((await package('entry:2')).status, PackageStatus.running);
    });
  });

  group('the queue', () {
    Future<void> seed() async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      ]);
    }

    test('pausing drops the queue and marks the row', () async {
      await seed();
      await manager.startPackage(const EntryPackage(1, 'Hallo'));
      await manager.pausePackage('entry:1');

      expect((await package('entry:1')).status, PackageStatus.paused);
      // Nothing left that a later start could pick up again.
      expect(
        await FileDownloader().database.allRecords(group: 'entry:1'),
        isEmpty,
      );
    });

    test('a paused row keeps its counts', () async {
      await queue('entry:1', 'Hallo', PackageStatus.running);
      await manager.start();

      final video = videoTask();
      await lay(video, bytes: 64);
      await report(video, TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final before = await package('entry:1');

      await manager.pausePackage('entry:1');
      // Late reports must not move the numbers on a package the user stopped.
      await report(videoTask(kind: AssetKind.thumbnail), TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final after = await package('entry:1');
      expect(after.status, PackageStatus.paused);
      expect(after.done, before.done);
    });

    test('resuming by id walks the same package again', () async {
      await seed();
      await manager.startPackage(const EntryPackage(1, 'Hallo'));
      await manager.pausePackage('entry:1');
      channels.enqueued.clear();

      // What the button in the notification calls, it only knows the group.
      await manager.resumeById('entry:1');
      expect(channels.enqueued, contains('951-video'));
    });

    test('resuming walks the same package again', () async {
      await seed();
      await manager.startPackage(const EntryPackage(1, 'Hallo'));
      channels.enqueued.clear();

      await manager.resumePackage(await package('entry:1'));
      expect(channels.enqueued, contains('951-video'));
    });

    test('resuming skips what is on disk', () async {
      await seed();
      final task = videoTask();
      await lay(task);
      await FileDownloader().database.updateRecord(
        TaskRecord(task, TaskStatus.complete, 1, 40),
      );
      await manager.reconcile();

      await manager.startPackage(const EntryPackage(1, 'Hallo'));
      expect(channels.enqueued, isNot(contains('951-video')));
      expect(channels.enqueued, contains('951-thumbnail'));
    });

    test('cancelling takes the row with it', () async {
      await seed();
      await manager.startPackage(const EntryPackage(1, 'Hallo'));
      await manager.cancelPackage('entry:1');

      expect(await db.select(db.packages).get(), isEmpty);
    });

    group('a button in the shade', () {
      /// The whole way in. The plugin hands the press to whoever registered,
      /// and start() is what registers. This used to be an argument main
      /// passed to initNotifications. When it went missing the buttons still
      /// drew and still woke the app and no test noticed because none of
      /// them ever pressed one.
      Future<void> press(String action, String id) async {
        packageActionHandler!(action, id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      test('pausing stops the package', () async {
        await seed();
        await manager.start();
        await manager.startPackage(const EntryPackage(1, 'Hallo'));

        await press('pause', 'entry:1');
        expect((await package('entry:1')).status, PackageStatus.paused);
      });

      test('resuming walks the package again', () async {
        await seed();
        await manager.start();
        await manager.startPackage(const EntryPackage(1, 'Hallo'));
        await manager.pausePackage('entry:1');
        channels.enqueued.clear();

        await press('resume', 'entry:1');
        expect(channels.enqueued, contains('951-video'));
      });

      test('aborting takes the row with it', () async {
        await seed();
        await manager.start();
        await manager.startPackage(const EntryPackage(1, 'Hallo'));

        await press('cancel', 'entry:1');
        expect(await db.select(db.packages).get(), isEmpty);
      });

      test('an action that is not ours leaves the row alone', () async {
        await seed();
        await manager.start();
        await manager.startPackage(const EntryPackage(1, 'Hallo'));
        final before = (await package('entry:1')).status;

        await press('weiterleiten', 'entry:1');
        expect((await package('entry:1')).status, before);
      });
    });

    test('a package without anything to fetch is done right away', () async {
      await cacheEntries(db, [sampleEntry(id: 2, text: 'Ohne')]);
      await manager.startPackage(const EntryPackage(2, 'Ohne'));

      final row = await package('entry:2');
      expect(row.status, PackageStatus.done);
      expect(row.total, 0);
    });

    test('a failing lookup leaves the reason on the row', () async {
      await manager.startPackage(const LetterPackage('B'));

      final row = await package('letter:B');
      expect(row.status, PackageStatus.error);
      expect(row.error, isNotNull);
    });

    test('the total stays the plan while the records come in', () async {
      await seed();
      await manager.start();
      await manager.startPackage(const EntryPackage(1, 'Hallo'));
      expect((await package('entry:1')).total, 2);

      // The native side writes one record per task as it takes them on. The
      // denominator used to follow that and climbed while the bar ran.
      await report(videoTask(), TaskStatus.enqueued);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final row = await package('entry:1');
      expect(row.total, 2);
      expect(row.done, 0);
    });

    test('a resumed package counts only what is left to fetch', () async {
      await seed();
      final video = videoTask();
      await lay(video);
      await FileDownloader().database.updateRecord(
        TaskRecord(video, TaskStatus.complete, 1, 40),
      );
      await manager.reconcile();

      await manager.start();
      await manager.startPackage(const EntryPackage(1, 'Hallo'));

      final thumb = videoTask(kind: AssetKind.thumbnail);
      await lay(thumb);
      await report(thumb, TaskStatus.complete);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // The record of the run before must not count into this one.
      final row = await package('entry:1');
      expect(row.total, 1);
      expect(row.done, 1);
    });

    test('starting a package asks for the notification permission', () async {
      await seed();
      channels.notificationsAllowed = false;
      await manager.startPackage(const EntryPackage(1, 'Hallo'));

      expect(
        channels.calls,
        contains('com.bbflight.background_downloader.requestPermission'),
      );
    });

    test('a permission already given is not asked for again', () async {
      await seed();
      await manager.startPackage(const EntryPackage(1, 'Hallo'));

      expect(
        channels.calls,
        isNot(contains('com.bbflight.background_downloader.requestPermission')),
      );
    });
  });

  group('what is on the device', () {
    test('removing deletes the files and the rows', () async {
      final task = videoTask();
      final file = await lay(task);
      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: 951,
              kind: AssetKind.video,
              entryId: 1,
              localPath: file.path,
              bytes: 40,
              downloadedAt: DateTime.now(),
            ),
          );

      expect(await manager.isDownloaded(1), isTrue);
      await manager.removeDownloads([1]);

      expect(file.existsSync(), isFalse);
      expect(await manager.isDownloaded(1), isFalse);
    });

    test('removing what is not there is quiet', () async {
      await manager.removeDownloads([99]);
      expect(await db.select(db.assets).get(), isEmpty);
    });
  });

  group('after a variant change', () {
    test('an entry that is offline gets the new clip', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      ]);
      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: 4,
              kind: AssetKind.video,
              entryId: 1,
              localPath: '${channels.tempDir.path}/media/4.mp4',
              bytes: 1,
              downloadedAt: DateTime.now(),
            ),
          );

      await refreshDownloadFor(db, 1);
      expect(channels.enqueued, contains('951-video'));
    });

    test('an entry that is not offline is left alone', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      ]);
      await refreshDownloadFor(db, 1);
      expect(channels.enqueued, isEmpty);
    });

    test('an entry the cache never saw is left alone', () async {
      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: 4,
              kind: AssetKind.video,
              entryId: 7,
              localPath: 'egal',
              bytes: 1,
              downloadedAt: DateTime.now(),
            ),
          );
      await refreshDownloadFor(db, 7);
      expect(channels.enqueued, isEmpty);
    });
  });

  test('a package row survives being written twice', () async {
    await queue('entry:1', 'Hallo', PackageStatus.queued);
    await (db.update(db.packages)..where((t) => t.id.equals('entry:1'))).write(
      const PackagesCompanion(done: Value(1)),
    );
    expect((await package('entry:1')).done, 1);
  });
}
