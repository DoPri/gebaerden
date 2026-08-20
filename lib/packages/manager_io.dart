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

const downloadsAvailable = true;

const _folder = 'media';
const _base = BaseDirectory.applicationSupport;

String _fileName(int videoId, AssetKind kind) =>
    kind == AssetKind.video ? '$videoId.mp4' : '$videoId.jpg';

String _taskId(int videoId, AssetKind kind) => '$videoId-${kind.name}';

class Downloads {
  Downloads(this._db);

  final AppDatabase _db;
  StreamSubscription<TaskUpdate>? _sub;

  // Debounce task table queries across bulk updates.
  final _dirty = <String>{};
  Timer? _flush;

  final _refreshing = <String>{};
  final _rerun = <String>{};

  Future<void> start() async {
    // Must listen before resumeFromBackground replays updates.
    _sub = FileDownloader().updates.listen(_onUpdate);

    // Clear stale notifications from killed processes.
    await hideAllPackages();
    _rows = _db.select(_db.packages).watch().listen(_mirrorAll);

    packageActionHandler = _onPackageAction;

    // Android kills background tasks after 9 minutes without foreground service.
    await FileDownloader().configure(
      androidConfig: (Config.runInForeground, Config.always),
    );

    await FileDownloader().trackTasks();
    // Replay background completions buffered while app was suspended.
    await FileDownloader().resumeFromBackground();
    await reconcile();

    // Drops orphaned records before reviving valid killed tasks.
    await _dropOrphans();
    await FileDownloader().rescheduleKilledTasks();
  }

  // Prevent rescheduleKilledTasks from restarting aborted packages.
  Future<void> _dropOrphans() async {
    final running = {
      for (final row in await (_db.select(
        _db.packages,
      )..where((t) => t.status.equalsValue(PackageStatus.running))).get())
        row.id,
    };

    for (final record in await FileDownloader().database.allRecords()) {
      if (record.status.isFinalState) continue;
      if (running.contains(record.task.group)) continue;
      await FileDownloader().database.deleteRecordWithId(record.taskId);
    }
  }

  // Avoid platform call delays in start/pause/cancel and prevent test deadlocks.
  StreamSubscription<List<StoredPackage>>? _rows;

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
    // System pauses on timeout or network loss; auto-resume immediately.
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

  // Prevent concurrent DB scans from writing stale progress out of order.
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

    // Atomic read-modify-write prevents overwriting a concurrent pause.
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

    if (row.status == PackageStatus.paused) return;

    final status = switch (row.status) {
      _ when open > 0 => PackageStatus.running,
      // Downloader records only exist once enqueued; total is the true yardstick.
      _ when settled < row.total => PackageStatus.running,
      // Upstream 403s on single assets are non-fatal unless all files fail.
      _ when failed > 0 && done == 0 => PackageStatus.error,
      _ when stopped => row.status,
      _ => PackageStatus.done,
    };

    await (_db.update(_db.packages)..where((t) => t.id.equals(group))).write(
      PackagesCompanion(
        done: Value(done),
        bytes: Value(bytes),
        status: Value(status),
        error: Value(failed == 0 ? null : '$failed Dateien fehlen'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // Scope asset query to video IDs extracted from task IDs.
  Future<int> _bytes(List<TaskRecord> records) async {
    final mine = records.map((r) => r.taskId).toSet();
    final videoIds = <int>{
      for (final task in mine) ?int.tryParse(task.split('-').first),
    };
    if (videoIds.isEmpty) return 0;

    final rows = await (_db.select(
      _db.assets,
    )..where((t) => t.videoId.isIn(videoIds))).get();
    return rows
        .where((a) => mine.contains(_taskId(a.videoId, a.kind)))
        .fold<int>(0, (sum, a) => sum + a.bytes);
  }

  Future<List<CachedEntry>> _resolve(PackageSpec spec) async {
    switch (spec) {
      case AllPackage():
        final all = <CachedEntry>[];
        // Letter search index is incomplete.
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
            // Parks task on timeout/network drop instead of failing.
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

  Future<void> _askForNotifications() async {
    final permissions = FileDownloader().permissions;
    const type = PermissionType.notifications;
    if (await permissions.status(type) == PermissionStatus.granted) return;
    // Guard against hanging native permission callback.
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
      // Prevent old task records from skewing progress counts.
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
      // Catch Error (e.g. JSON cast failures) to prevent stuck queued status.
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

  // Enqueue in chunks to allow fast pause/cancel response.
  static const _block = 50;

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
      if (row == null || row.status != PackageStatus.running) return;

      await FileDownloader().enqueueAll(tasks.skip(at).take(_block));
    }
  }

  // reset avoids slow item-by-item cancel; record deletion prevents revival.
  Future<void> _stop(String id) async {
    // Ensure in-flight chunk finishes before reset.
    await _feeding[id];
    await FileDownloader().reset(group: id);
    await FileDownloader().database.deleteAllRecords(group: id);
  }

  void _onPackageAction(String action, String group) {
    unawaited(switch (action) {
      'pause' => pausePackage(group),
      'resume' => resumeById(group),
      'cancel' => cancelPackage(group),
      _ => Future<void>.value(),
    });
  }

  Future<void> pausePackage(String id) async {
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
    await (_db.delete(_db.packages)..where((t) => t.id.equals(id))).go();
    await _stop(id);
  }

  Future<void> reconcile() async {
    final records = await FileDownloader().database.allRecords();
    final assets = await _db.select(_db.assets).get();
    final known = {for (final a in assets) _taskId(a.videoId, a.kind)};

    // Avoid rewriting thousands of already cached asset records.
    for (final record in records) {
      if (record.status != TaskStatus.complete) continue;
      if (known.contains(record.taskId)) continue;
      await _record(record.task);
    }

    // Purge records if files were deleted externally.
    final gone = assets.where((a) => !File(a.localPath).existsSync()).toList();
    if (gone.isNotEmpty) {
      await _db.batch((b) {
        for (final asset in gone) {
          b.delete(_db.assets, asset);
        }
      });
    }

    // Running packages with no active native tasks were killed.
    final busy = records
        .where((r) => !r.status.isFinalState)
        .map((r) => r.task.group)
        .toSet();

    final running = await (_db.select(
      _db.packages,
    )..where((t) => t.status.equalsValue(PackageStatus.running))).get();
    for (final row in running.where((r) => !busy.contains(r.id))) {
      // Mark queued so subsequent updates can revive it; paused is user-only.
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

late Downloads downloads;

Future<void> refreshDownloadFor(AppDatabase db, int entryId) async {
  if (!await downloads.isDownloaded(entryId)) return;
  final entry = await getEntry(db, entryId);
  if (entry == null) return;
  await downloads.startPackage(EntryPackage(entryId, entry.word));
}
