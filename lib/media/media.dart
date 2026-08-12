import 'package:drift/drift.dart';

import '../db/database.dart';
import '../platform/local.dart';
import 'variants.dart';

/// A downloaded copy wins over the CDN.
class MediaSource {
  const MediaSource.file(String this.path) : url = null;
  const MediaSource.network(String this.url) : path = null;

  final String? path;
  final String? url;

  bool get isFile => path != null;
}

Future<Map<int, String>> _localPaths(
  AppDatabase db,
  List<int> videoIds,
  AssetKind kind,
) async {
  if (videoIds.isEmpty) return {};
  final rows = await (db.select(
    db.assets,
  )..where((t) => t.videoId.isIn(videoIds) & t.kind.equalsValue(kind))).get();
  return {for (final row in rows) row.videoId: row.localPath};
}

Future<MediaSource?> resolveMedia(
  AppDatabase db,
  ApiVideo? video,
  AssetKind kind,
) async {
  if (video == null) return null;
  final remote = kind == AssetKind.video ? video.videoUrl : video.thumbnailUrl;

  final local = (await _localPaths(db, [video.id], kind))[video.id];
  // A row can outlive the file.
  if (local != null && localExists(local)) return MediaSource.file(local);

  return remote == null ? null : MediaSource.network(remote);
}

/// Honors the selected variant.
Future<Map<int, MediaSource>> thumbnailsFor(
  AppDatabase db,
  List<CachedEntry> entries,
) async {
  final videos = await preferredVideos(db, entries);
  if (videos.isEmpty) return {};

  final local = await _localPaths(
    db,
    videos.values.map((v) => v.id).toList(),
    AssetKind.thumbnail,
  );

  final sources = <int, MediaSource>{};
  for (final entry in entries) {
    final video = videos[entry.id];
    if (video == null) continue;

    final path = local[video.id];
    if (path != null && localExists(path)) {
      sources[entry.id] = MediaSource.file(path);
    } else if (video.thumbnailUrl != null) {
      sources[entry.id] = MediaSource.network(video.thumbnailUrl!);
    }
  }
  return sources;
}
