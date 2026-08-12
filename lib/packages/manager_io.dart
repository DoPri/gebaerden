// The native download queue. background_downloader has no web build and
// imports dart:io, so nothing here is reachable from the web build.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart';

import '../api/queries.dart';
import '../db/database.dart';
import '../db/lists.dart';
import '../db/repo.dart';
import '../media/variants.dart';
import '../platform/notify.dart';
import '../search/dictionary.dart';
import 'spec.dart';

export 'spec.dart';

/// The queue is there, so the screens that drive it are worth showing.
const downloadsAvailable = true;

const _folder = 'media';
const _base = BaseDirectory.applicationSupport;

String _fileName(int videoId, AssetKind kind) =>
    kind == AssetKind.video ? '$videoId.mp4' : '$videoId.jpg';

String _taskId(int videoId, AssetKind kind) => '$videoId-${kind.name}';

/// The native side keeps the queue, so downloads survive the app being frozen
/// or swiped away.
class Downloads {
  Downloads(this._db);

  final AppDatabase _db;
  StreamSubscription<TaskUpdate>? _sub;

  /// A package of several thousand files fires as many updates. Recounting on
  /// each one would read the whole task table every time.
  final _dirty = <String>{};
  Timer? _flush;

  /// One refresh per package at a time, plus a note to run it again.
  final _refreshing = <String>{};
  final _rerun = <String>{};

  Future<void> start() async {
    // The listener has to stand first, what follows replays updates.
    _sub = FileDownloader().updates.listen(_onUpdate);

    // An ongoing notification outlives the process, and a package that was
    // cancelled while the app was gone has no row left to take it down.
    await hideAllPackages();
    _rows = _db.select(_db.packages).watch().listen(_mirrorAll);

    // The buttons in the shade end up here. Whoever runs the queue answers
    // them, so there is no wiring left for main to forget.
    packageActionHandler = _onPackageAction;

    // Without a foreground service Android ends a task after nine minutes and
    // drops the rest soon after the app goes away. The screen promises the
    // opposite. A running notification is the price, it is configured above.
    await FileDownloader().configure(
      androidConfig: (Config.runInForeground, Config.always),
    );

    await FileDownloader().trackTasks();
    // Whatever the native side finished while the app was gone is buffered
    // until it is asked for. Without this the records stay at the state of
    // the last suspend, and every count below is read off stale rows.
    await FileDownloader().resumeFromBackground();
    await reconcile();

    // Tasks that were killed along with the app are gone from the native
    // queue, only their records are left. This puts them back. It runs after
    // reconcile because it drops the very records reconcile reads.
    await _dropOrphans();
    await FileDownloader().rescheduleKilledTasks();
  }

  /// Throws away the open records of every package that is not running.
  ///
  /// Stopping a package deletes its records, but the app does not always live
  /// long enough to finish that. What was left behind looked to
  /// rescheduleKilledTasks like a task that wanted to come back, so an aborted
  /// download started itself again on the next launch. Only a package the
  /// screen still shows as running may be revived.
  Future<void> _dropOrphans() async {
    final running = {
      for (final row in await (_db.select(
        _db.packages,
      )..where((t) => t.status.equalsValue(PackageStatus.running))).get())
        row.id,
    };

    for (final record in await FileDownloader().database.allRecords()) {
      // Finished records stay: reconcile and the counts read them.
      if (record.status.isFinalState) continue;
      if (running.contains(record.task.group)) continue;
      await FileDownloader().database.deleteRecordWithId(record.taskId);
    }
  }

  /// The shade follows the package table, nothing else.
  ///
  /// Driven by the table's own change stream, not by the code that starts,
  /// pauses or cancels: those must not wait on a platform call, and an extra
  /// read of their own was enough to deadlock the widget tests. This way the
  /// notification cannot say anything the offline screen does not say, because
  /// both read the same rows.
  StreamSubscription<List<StoredPackage>>? _rows;

  /// What the shade already shows, so an unchanged row is not posted again.
  final _shown = <String, String>{};

  Future<void> _mirrorAll(List<StoredPackage> rows) async {
    for (final id in _shown.keys.toSet()) {
      if (!rows.any((r) => r.id == id)) {
        _shown.remove(id);
        await hidePackage(id);
      }
    }
    for (final row in rows) {
      final state = '${row.status}|${row.done}|${row.total}|${row.error}';
      if (_shown[row.id] == state) continue;
      _shown[row.id] = state;
      await _mirror(row);
    }
  }

  Future<void> _mirror(StoredPackage row) async {
    if (row.status == PackageStatus.done) {
      await hidePackage(row.id);
      return;
    }
    await showPackage(
      group: row.id,
      label: row.label,
      done: row.done,
      total: row.total,
      paused: row.status == PackageStatus.paused,
      note: row.status == PackageStatus.error ? row.error : null,
    );
  }

  Future<void> dispose() async {
    _flush?.cancel();
    packageActionHandler = null;
    await _rows?.cancel();
    await _sub?.cancel();
  }

  Future<void> _onUpdate(TaskUpdate update) async {
    if (update is! TaskStatusUpdate) return;
    // Nobody here asks for a pause, that goes through cancel. The system does,
    // when a task times out or the network drops, and then it waits for us.
    final task = update.task;
    if (update.status == TaskStatus.paused && task is DownloadTask) {
      unawaited(FileDownloader().resume(task));
    }
    if (update.status == TaskStatus.complete) await _record(update.task);

    _dirty.add(update.task.group);
    _flush ??= Timer(const Duration(milliseconds: 400), () {
      _flush = null;
      final groups = _dirty.toList();
      _dirty.clear();
      for (final group in groups) {
        unawaited(_refresh(group));
      }
    });
  }

  /// Counting a package of several thousand files takes seconds, and a new
  /// timer fires every 400 milliseconds. Left alone, a dozen of these ran at
  /// once and the slowest wrote its stale snapshot last: the job flipped
  /// between running and done, so the bar vanished and came back, and the
  /// counts jumped around.
  Future<void> _refresh(String group) async {
    if (!_refreshing.add(group)) {
      _rerun.add(group);
      return;
    }
    try {
      await _refreshRow(group);
    } finally {
      _refreshing.remove(group);
      if (_rerun.remove(group)) unawaited(_refresh(group));
    }
  }

  Future<void> _record(Task task) async {
    final meta = jsonDecode(task.metaData) as Map<String, dynamic>;
    final path = await task.filePath();
    final file = File(path);
    if (!file.existsSync()) return;

    await _db
        .into(_db.assets)
        .insertOnConflictUpdate(
          StoredAsset(
            videoId: meta['videoId'] as int,
            kind: AssetKind.values.byName(meta['kind'] as String),
            entryId: meta['entryId'] as int,
            localPath: path,
            bytes: file.lengthSync(),
            downloadedAt: DateTime.now(),
          ),
        );
  }

  Future<void> _refreshRow(String group) async {
    final known = await (_db.select(
      _db.packages,
    )..where((t) => t.id.equals(group))).getSingleOrNull();
    if (known == null) return;

    final records = await FileDownloader().database.allRecords(group: group);
    final done = records.where((r) => r.status == TaskStatus.complete).length;
    final failed = records.where((r) => r.status == TaskStatus.failed).length;
    final open = records.where((r) => !r.status.isFinalState).length;
    final settled = records.where((r) => r.status.isFinalState).length;
    final stopped = records.any((r) => r.status == TaskStatus.canceled);
    final bytes = await _bytes(records);

    // Counting takes seconds on a package of several thousand files, long
    // enough for a pause to land in between. Reading the row and writing it
    // back therefore happens in one go. Otherwise this puts back the running
    // it saw before the pause and the package carries on.
    await _db.transaction(
      () => _write(group, done, failed, open, settled, stopped, bytes),
    );
  }

  Future<void> _write(
    String group,
    int done,
    int failed,
    int open,
    int settled,
    bool stopped,
    int bytes,
  ) async {
    final row = await (_db.select(
      _db.packages,
    )..where((t) => t.id.equals(group))).getSingleOrNull();
    if (row == null) return;

    // The user asked for the stop, so nothing here touches the row: not the
    // status, not the counts. Only a resume or a cancel leaves this state.
    if (row.status == PackageStatus.paused) return;

    final status = switch (row.status) {
      _ when open > 0 => PackageStatus.running,
      // A record appears when the native side takes a task on, so early in a
      // big package every record it knows can be complete at once. Without the
      // plan as the yardstick that read as done, at 411 of 8488 files.
      _ when settled < row.total => PackageStatus.running,
      // Single files are missing upstream, a 403 on a thumbnail is normal.
      // Failing the whole package over one of them dropped it out of the job
      // list, which shows running, paused and queued, and the download looked
      // like it had vanished. Only a package that got nothing is an error.
      _ when failed > 0 && done == 0 => PackageStatus.error,
      // All canceled and the row was not paused: keep what it had rather than
      // call it done, a resume re-enqueues what is missing.
      _ when stopped => row.status,
      _ => PackageStatus.done,
    };

    // total stays what startPackage planned. Counting the records instead let
    // the number climb while enqueueAll was still walking the list, so the bar
    // ran backwards and never reached its end.
    await (_db.update(_db.packages)..where((t) => t.id.equals(group))).write(
      PackagesCompanion(
        done: Value(done),
        bytes: Value(bytes),
        status: Value(status),
        // Kept even when the package counts as done, it is the only trace of
        // what was left behind.
        error: Value(failed == 0 ? null : '$failed Dateien fehlen'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// What this group holds on disk. The task ids carry the video, so the query
  /// stays on those rows instead of reading every asset on every progress tick.
  Future<int> _bytes(List<TaskRecord> records) async {
    final mine = records.map((r) => r.taskId).toSet();
    final videoIds = <int>{
      for (final task in mine) ?int.tryParse(task.split('-').first),
    };
    if (videoIds.isEmpty) return 0;

    final rows = await (_db.select(
      _db.assets,
    )..where((t) => t.videoId.isIn(videoIds))).get();
    // Video and thumbnail share a videoId, so the kind still has to match.
    return rows
        .where((a) => mine.contains(_taskId(a.videoId, a.kind)))
        .fold<int>(0, (sum, a) => sum + a.bytes);
  }

  Future<List<CachedEntry>> _resolve(PackageSpec spec) async {
    switch (spec) {
      case AllPackage():
        final all = <CachedEntry>[];
        // Letter search misses ~600 entries.
        await for (final batch in iterateIndex()) {
          all.addAll(await cacheEntries(_db, batch));
        }
        return all;
      case LetterPackage(:final letter):
        return liveLetter(_db, letter);
      case ListPackage(:final listId):
        return getEntries(_db, await listEntryIds(_db, listId));
      case EntryPackage(:final entryId):
        return getEntries(_db, [entryId]);
    }
  }

  Future<List<DownloadTask>> _tasks(
    String group,
    List<CachedEntry> entries,
  ) async {
    final videos = await preferredVideos(_db, entries);
    final have = {
      for (final row in await _db.select(_db.assets).get())
        '${row.videoId}-${row.kind.name}',
    };

    final tasks = <DownloadTask>[];
    for (final entry in entries) {
      final video = videos[entry.id];
      if (video?.videoUrl == null) continue;

      for (final (kind, url) in [
        (AssetKind.video, video!.videoUrl),
        (AssetKind.thumbnail, video.thumbnailUrl),
      ]) {
        if (url == null) continue;
        final id = _taskId(video.id, kind);
        if (have.contains(id)) continue;

        tasks.add(
          DownloadTask(
            taskId: id,
            url: url,
            filename: _fileName(video.id, kind),
            directory: _folder,
            baseDirectory: _base,
            group: group,
            updates: Updates.statusAndProgress,
            retries: 3,
            // Lets the system park a task instead of failing it when it times
            // out or the network drops. _onUpdate picks it back up.
            allowPause: true,
            metaData: jsonEncode({
              'videoId': video.id,
              'kind': kind.name,
              'entryId': entry.id,
            }),
          ),
        );
      }
    }
    return tasks;
  }

  /// The downloader shows no notification at all without this, and a package
  /// that reports nothing while the app is away looks stuck.
  Future<void> _askForNotifications() async {
    final permissions = FileDownloader().permissions;
    const type = PermissionType.notifications;
    if (await permissions.status(type) == PermissionStatus.granted) return;
    // The answer arrives through a native callback. If it never does, the
    // download still has to start, so this waits with an end to it.
    await permissions
        .request(type)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => PermissionStatus.denied,
        );
  }

  Future<void> startPackage(PackageSpec spec) async {
    await _askForNotifications();
    await _db
        .into(_db.packages)
        .insertOnConflictUpdate(
          StoredPackage(
            id: spec.id,
            label: spec.label,
            spec: jsonEncode(spec.toJson()),
            status: PackageStatus.queued,
            done: 0,
            total: 0,
            bytes: 0,
            updatedAt: DateTime.now(),
          ),
        );

    try {
      final tasks = await _tasks(spec.id, await _resolve(spec));
      // The records of an earlier run would be counted into this one, and a
      // resumed package would report more finished files than it has to fetch.
      await FileDownloader().database.deleteAllRecords(group: spec.id);
      await (_db.update(
        _db.packages,
      )..where((t) => t.id.equals(spec.id))).write(
        PackagesCompanion(
          done: const Value(0),
          total: Value(tasks.length),
          bytes: const Value(0),
          status: Value(
            tasks.isEmpty ? PackageStatus.done : PackageStatus.running,
          ),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _enqueue(spec.id, tasks);
      // Object, not Exception. A cast that fails on unexpected api json is an
      // Error, and letting it through would leave the row queued forever.
    } on Object catch (err) {
      await (_db.update(
        _db.packages,
      )..where((t) => t.id.equals(spec.id))).write(
        PackagesCompanion(
          status: const Value(PackageStatus.error),
          error: Value('$err'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Hands the tasks over in blocks and looks at the row between them.
  ///
  /// enqueueAll passes the whole list to the platform in one call, and the
  /// native side then walks it on its own for minutes. A pause in that window
  /// stopped the handful of tasks that had reached the queue while the loop
  /// kept feeding thousands more behind it, so the download carried on and the
  /// counters on the offline screen kept climbing. A block is small enough
  /// that a stop takes hold within a second.
  static const _block = 50;

  /// The hand-over that is currently running, per package, so a stop can wait
  /// for it instead of racing it.
  final _feeding = <String, Future<void>>{};

  Future<void> _enqueue(String id, List<DownloadTask> tasks) async {
    final feed = _feed(id, tasks);
    _feeding[id] = feed;
    try {
      await feed;
    } finally {
      _feeding.remove(id);
    }
  }

  Future<void> _feed(String id, List<DownloadTask> tasks) async {
    for (var at = 0; at < tasks.length; at += _block) {
      final row = await (_db.select(
        _db.packages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      // Paused, cancelled or gone: whatever is queued stays, nothing new.
      if (row == null || row.status != PackageStatus.running) return;

      await FileDownloader().enqueueAll(tasks.skip(at).take(_block));
    }
  }

  /// Stops everything in the group and leaves nothing that could restart it.
  ///
  /// The records go first. They are the only trace a task leaves behind, and
  /// rescheduleKilledTasks puts every enqueued one back on the next start. If
  /// the app died while the queue was still draining, the paused or aborted
  /// package simply carried on the next time it was opened.
  ///
  /// reset is a single call into the platform. cancelAll reads every task out
  /// through an isolate and cancels them one by one from Dart, which took
  /// minutes for a package of several thousand files and kept downloading for
  /// all of it.
  Future<void> _stop(String id) async {
    // The block still being handed to the platform has to land before the
    // reset, otherwise it arrives after it and downloads on. The loop above
    // reads the row between blocks and the row already says stop, so this
    // waits for one block at most. No polling, no timers: a wall clock delay
    // here never fires under the widget test clock and hung the suite.
    await _feeding[id];
    await FileDownloader().reset(group: id);
    // Last, so nothing is left for rescheduleKilledTasks to bring back.
    await FileDownloader().database.deleteAllRecords(group: id);
  }

  /// A button in the shade. The press lands on the main isolate, so it can go
  /// straight to the queue. Nothing is awaited: the plugin hands us a void
  /// callback and does not wait, and an unknown action is simply not ours.
  void _onPackageAction(String action, String group) {
    unawaited(switch (action) {
      'pause' => pausePackage(group),
      'resume' => resumeById(group),
      'cancel' => cancelPackage(group),
      _ => Future<void>.value(),
    });
  }

  /// Pause drops the queue. Resuming re-walks it and skips what is on disk.
  Future<void> pausePackage(String id) async {
    // The row goes first, so the screen answers the tap right away.
    await (_db.update(_db.packages)..where((t) => t.id.equals(id))).write(
      PackagesCompanion(
        status: const Value(PackageStatus.paused),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _stop(id);
  }

  Future<void> resumeById(String id) async {
    final row = await (_db.select(
      _db.packages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row != null) await resumePackage(row);
  }

  Future<void> resumePackage(StoredPackage row) => startPackage(
    PackageSpec.fromJson(jsonDecode(row.spec) as Map<String, dynamic>),
  );

  Future<void> cancelPackage(String id) async {
    // The row goes first, same as pausing. Once it is gone the refresh above
    // ignores the group anyway.
    await (_db.delete(_db.packages)..where((t) => t.id.equals(id))).go();
    await _stop(id);
  }

  /// Writes the rows for files the native side finished while the app was gone.
  Future<void> reconcile() async {
    final records = await FileDownloader().database.allRecords();
    final assets = await _db.select(_db.assets).get();
    final known = {for (final a in assets) _taskId(a.videoId, a.kind)};

    // Only what is missing. Rewriting every finished task would mean thousands
    // of writes on every return to the app.
    for (final record in records) {
      if (record.status != TaskStatus.complete) continue;
      if (known.contains(record.taskId)) continue;
      await _record(record.task);
    }

    // A row can outlive its file, for instance after the user clears storage.
    final gone = assets.where((a) => !File(a.localPath).existsSync()).toList();
    if (gone.isNotEmpty) {
      // By row, video and thumbnail can go missing one without the other.
      await _db.batch((b) {
        for (final asset in gone) {
          b.delete(_db.assets, asset);
        }
      });
    }

    // A row on running with nothing open behind it is a leftover from a kill.
    // Per group: one package that finished must not park another that runs.
    // start() has replayed the missed updates by now, so the records are as
    // fresh as they get without asking the platform, which costs an isolate.
    final busy = records
        .where((r) => !r.status.isFinalState)
        .map((r) => r.task.group)
        .toSet();

    final running = await (_db.select(
      _db.packages,
    )..where((t) => t.status.equalsValue(PackageStatus.running))).get();
    for (final row in running.where((r) => !busy.contains(r.id))) {
      // queued, not paused. paused is the user's word and _write keeps that
      // one until a resume. A guess made here has to give way as soon as an
      // update proves the package is running after all.
      await (_db.update(_db.packages)..where((t) => t.id.equals(row.id))).write(
        const PackagesCompanion(status: Value(PackageStatus.queued)),
      );
    }
  }

  Future<void> removeDownloads(List<int> entryIds) async {
    final assets = await (_db.select(
      _db.assets,
    )..where((t) => t.entryId.isIn(entryIds))).get();

    for (final asset in assets) {
      final file = File(asset.localPath);
      if (file.existsSync()) file.deleteSync();
    }
    await (_db.delete(_db.assets)..where((t) => t.entryId.isIn(entryIds))).go();
  }

  Future<bool> isDownloaded(int entryId) async {
    final rows = await (_db.select(
      _db.assets,
    )..where((t) => t.entryId.equals(entryId))).get();
    return rows.isNotEmpty;
  }
}

/// Set once at startup so screens can reach the queue without threading it
/// through every constructor.
late Downloads downloads;

/// After a variant change, fetch the new clip if the entry is already offline.
Future<void> refreshDownloadFor(AppDatabase db, int entryId) async {
  if (!await downloads.isDownloaded(entryId)) return;
  final entry = await getEntry(db, entryId);
  if (entry == null) return;
  await downloads.startPackage(EntryPackage(entryId, entry.word));
}
