import 'dart:async';

import 'package:drift/drift.dart';

import 'database.dart';

/// ~38% of the corpus has no footage.
EntriesCompanion toCached(ApiEntry entry) {
  final videos = entry.videos;
  final current =
      entry.currentVideo ?? (videos?.isNotEmpty == true ? videos!.first : null);
  final description = entry.description?.trim();

  return EntriesCompanion.insert(
    id: Value(entry.id),
    word: entry.text,
    type: Value(entry.type),
    description: Value(description?.isNotEmpty == true ? description : null),
    language: Value(entry.language),
    hasVideo: current?.videoUrl != null,
    currentVideo: Value(current),
    videos: Value(videos),
    cachedAt: DateTime.now(),
  );
}

/// Counts writes to the entry cache. The offline index keys off it, the write
/// below is an upsert and can change a word under a standing id, which no row
/// count would show.
int entriesRevision = 0;

/// Fires after every write to the entry cache. The trainer takes its counts
/// once, when the tab is built. On a fresh install the dictionary only lands
/// afterwards, in the background, and the tab would otherwise keep showing the
/// zero it read before the first page arrived.
final _entryWrites = StreamController<int>.broadcast();
Stream<int> get entryWrites => _entryWrites.stream;

/// Keeps detail videos when a list response overwrites the row.
Future<List<CachedEntry>> cacheEntries(
  AppDatabase db,
  List<ApiEntry> entries,
) async {
  if (entries.isEmpty) return [];
  entriesRevision++;
  _entryWrites.add(entriesRevision);

  return db.transaction(() async {
    final ids = entries.map((e) => e.id).toList();
    final existing = {
      for (final row in await (db.select(
        db.entries,
      )..where((t) => t.id.isIn(ids))).get())
        row.id: row,
    };

    final rows = <EntriesCompanion>[];
    for (final entry in entries) {
      var row = toCached(entry);
      if (row.videos.value == null) {
        row = row.copyWith(videos: Value(existing[entry.id]?.videos));
      }
      rows.add(row);
    }

    await db.batch((b) => b.insertAllOnConflictUpdate(db.entries, rows));
    return (db.select(db.entries)..where((t) => t.id.isIn(ids))).get();
  });
}

Future<CachedEntry?> getEntry(AppDatabase db, int id) =>
    (db.select(db.entries)..where((t) => t.id.equals(id))).getSingleOrNull();

Future<List<CachedEntry>> getEntries(AppDatabase db, List<int> ids) async {
  if (ids.isEmpty) return [];
  final rows = await (db.select(
    db.entries,
  )..where((t) => t.id.isIn(ids))).get();
  // Callers expect their own order back.
  final byId = {for (final row in rows) row.id: row};
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
}
