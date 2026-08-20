import '../api/client.dart';
import '../api/queries.dart';
import '../db/database.dart';
import '../db/repo.dart';

const _hintKey = 'index:lastPage';

// Page window limit to bypass scanner spam at index tail.
const _maxPages = 14;

Future<int> _hint(AppDatabase db) async {
  final row = await (db.select(
    db.settings,
  )..where((t) => t.key.equals(_hintKey))).getSingleOrNull();
  final value = row?.value;
  return value is int ? value : indexPages;
}

/// Walks backwards from index tail to skip video-less entries.
Future<List<CachedEntry>> newestEntries(
  AppDatabase db, {
  int limit = 60,
  CancelToken? cancel,
}) async {
  final last = await lastIndexPage(hint: await _hint(db), cancel: cancel);
  await db
      .into(db.settings)
      .insertOnConflictUpdate(StoredSetting(key: _hintKey, value: last));

  final batches = <List<ApiEntry>>[];
  var usable = 0;

  for (
    var page = last;
    page >= 1 && batches.length < _maxPages && usable < limit;
    page--
  ) {
    final batch = await fetchIndexPage(page, cancel: cancel);
    batches.insert(0, batch);
    usable += batch.where((e) => e.currentVideo?.videoUrl != null).length;
  }

  final rows = await cacheEntries(db, [for (final b in batches) ...b]);
  // Sorts by ID descending to present newest entries first.
  final playable = rows.where((r) => r.hasVideo).toList()
    ..sort((a, b) => b.id.compareTo(a.id));
  return playable.take(limit).toList();
}
