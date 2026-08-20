import '../api/client.dart';
import '../api/queries.dart';
import '../db/database.dart';
import '../db/repo.dart';

const _syncedKey = 'index:synced';

/// Checks sync flag; row counts cannot distinguish a full sync from partial cache.
Future<bool> dictionarySynced(AppDatabase db) async {
  final row = await (db.select(
    db.settings,
  )..where((t) => t.key.equals(_syncedKey))).getSingleOrNull();
  return row?.value == true;
}

/// Populates local cache with index metadata required by trainer and offline search.
Future<int> syncDictionary(AppDatabase db, {CancelToken? cancel}) async {
  var seen = 0;
  await for (final batch in iterateIndex(cancel: cancel)) {
    await cacheEntries(db, batch);
    seen += batch.length;
  }

  // Marks synced only after full index walk finishes successfully.
  await db
      .into(db.settings)
      .insertOnConflictUpdate(StoredSetting(key: _syncedKey, value: true));
  return seen;
}

/// Runs initial dictionary sync during startup, swallowing errors to prevent crash.
Future<bool> syncDictionaryOnce(AppDatabase db, {CancelToken? cancel}) async {
  try {
    if (await dictionarySynced(db)) return true;
    await syncDictionary(db, cancel: cancel);
    return true;
  } catch (_) {
    return false;
  }
}
