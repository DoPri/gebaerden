import 'package:drift/drift.dart';

import '../db/database.dart';

/// Every screen resolves its video through this module.
Future<void> setPreferred(AppDatabase db, int entryId, ApiVideo video) async {
  await db
      .into(db.variants)
      .insertOnConflictUpdate(
        VariantsCompanion.insert(
          entryId: Value(entryId),
          videoId: video.id,
          video: Value(video),
          at: DateTime.now(),
        ),
      );
}

Future<void> clearPreferred(AppDatabase db, int entryId) async {
  await (db.delete(db.variants)..where((t) => t.entryId.equals(entryId))).go();
}

/// Fresh beats the stored copy beats currentVideo.
ApiVideo? _resolve(CachedEntry entry, StoredVariant? pick) {
  if (pick == null) return entry.currentVideo;

  for (final video in entry.videos ?? const <ApiVideo>[]) {
    if (video.id == pick.videoId) return video;
  }
  if (entry.currentVideo?.id == pick.videoId) return entry.currentVideo;
  return pick.video ?? entry.currentVideo;
}

Future<ApiVideo?> preferredVideo(AppDatabase db, CachedEntry entry) async {
  final pick = await (db.select(
    db.variants,
  )..where((t) => t.entryId.equals(entry.id))).getSingleOrNull();
  return _resolve(entry, pick);
}

/// One query for a whole list.
Future<Map<int, ApiVideo>> preferredVideos(
  AppDatabase db,
  List<CachedEntry> entries,
) async {
  if (entries.isEmpty) return {};

  final ids = entries.map((e) => e.id).toList();
  final picks = {
    for (final row in await (db.select(
      db.variants,
    )..where((t) => t.entryId.isIn(ids))).get())
      row.entryId: row,
  };

  final resolved = <int, ApiVideo>{};
  for (final entry in entries) {
    final video = _resolve(entry, picks[entry.id]);
    if (video != null) resolved[entry.id] = video;
  }
  return resolved;
}
