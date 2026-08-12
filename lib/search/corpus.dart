import '../api/client.dart';
import '../api/queries.dart';
import '../db/database.dart';
import '../db/repo.dart';

/// Set once the whole index has been walked.
const _syncedKey = 'index:synced';

/// Whether the entry cache has ever seen the complete dictionary. Rows alone
/// cannot answer that since browsing a single word leaves a cache that is not empty
/// and still knows almost nothing.
Future<bool> dictionarySynced(AppDatabase db) async {
  final row = await (db.select(
    db.settings,
  )..where((t) => t.key.equals(_syncedKey))).getSingleOrNull();
  return row?.value == true;
}

/// Walks the complete index into the entry cache and returns how many entries
/// it wrote.
///
/// The trainer draws its candidates from that cache and nothing used to fill
/// it. On a fresh install it was empty, so Lernen counted zero new and zero
/// due. Letter search is no substitute, it misses ~600 entries. Only index()
/// is complete. This fetches metadata, not footage. The videos stay with the
/// offline packages, which is why a full walk costs a few hundred kilobytes
/// rather than half a gigabyte.
Future<int> syncDictionary(AppDatabase db, {CancelToken? cancel}) async {
  var seen = 0;
  await for (final batch in iterateIndex(cancel: cancel)) {
    await cacheEntries(db, batch);
    seen += batch.length;
  }

  // Last, so a walk that broke off halfway is not remembered as complete.
  await db
      .into(db.settings)
      .insertOnConflictUpdate(StoredSetting(key: _syncedKey, value: true));
  return seen;
}

/// Runs [syncDictionary] unless it has already run once, and reports whether
/// the cache now holds the dictionary.
///
/// Never throws, whatever goes wrong. This is started unwatched while the app
/// boots. No one is waiting on the result, so anything escaping here would
/// surface as an unhandled async error rather than as a message. Offline is
/// the ordinary case and not worth a word on screen, and a database that went
/// away underneath it, as it does when a test tears down, must not take the
/// app with it either. The marker stays unset, so the next start tries again.
Future<bool> syncDictionaryOnce(AppDatabase db, {CancelToken? cancel}) async {
  try {
    if (await dictionarySynced(db)) return true;
    await syncDictionary(db, cancel: cancel);
    return true;
  } catch (_) {
    return false;
  }
}
