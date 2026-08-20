import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/media/variants.dart';

import 'support.dart';

const _other = ApiVideo(
  id: 4711,
  videoUrl: 'https://example.invalid/other.mp4',
  thumbnailUrl: 'https://example.invalid/other.jpg',
  userName: 'Zweite Quelle',
);

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  Future<CachedEntry> seed({List<ApiVideo>? videos}) async {
    final rows = await cacheEntries(db, [
      sampleEntry(currentVideo: sampleVideo, videos: videos),
    ]);
    return rows.single;
  }

  test('without a pick currentVideo wins', () async {
    final entry = await seed();
    expect((await preferredVideo(db, entry))?.id, sampleVideo.id);
  });

  test('the picked variant wins', () async {
    final entry = await seed(videos: const [sampleVideo, _other]);
    await setPreferred(db, entry.id, _other);
    expect((await preferredVideo(db, entry))?.id, _other.id);
  });

  test('the fresh video beats the stored copy', () async {
    final entry = await seed(videos: const [sampleVideo, _other]);
    await setPreferred(db, entry.id, _other);

    // Stale cached URL replaced upstream.
    const refreshed = ApiVideo(
      id: 4711,
      videoUrl: 'https://example.invalid/neu.mp4',
    );
    final updated = (await cacheEntries(db, [
      sampleEntry(
        currentVideo: sampleVideo,
        videos: const [sampleVideo, refreshed],
      ),
    ])).single;

    expect(
      (await preferredVideo(db, updated))?.videoUrl,
      'https://example.invalid/neu.mp4',
    );
  });

  test('the copy carries while the entry has no variants', () async {
    var entry = await seed(videos: const [sampleVideo, _other]);
    await setPreferred(db, entry.id, _other);

    // Search results omit variants.
    entry = entry.copyWith(videos: const Value(null));
    expect((await preferredVideo(db, entry))?.id, _other.id);
  });

  test('points at a variant that is gone', () async {
    var entry = await seed(videos: const [sampleVideo, _other]);
    await setPreferred(db, entry.id, _other);

    // Selected variant deleted upstream.
    await (db.delete(
      db.variants,
    )..where((t) => t.entryId.equals(entry.id))).go();
    await db
        .into(db.variants)
        .insert(
          VariantsCompanion.insert(
            entryId: Value(entry.id),
            videoId: 999,
            at: DateTime.now(),
          ),
        );
    entry = (await getEntries(db, [entry.id])).single;

    expect((await preferredVideo(db, entry))?.id, sampleVideo.id);
  });

  test('clearing falls back to currentVideo', () async {
    final entry = await seed(videos: const [sampleVideo, _other]);
    await setPreferred(db, entry.id, _other);
    await clearPreferred(db, entry.id);
    expect((await preferredVideo(db, entry))?.id, sampleVideo.id);
  });

  test('preferredVideos resolves a whole list in one query', () async {
    await cacheEntries(db, [
      sampleEntry(
        id: 1,
        text: 'A',
        currentVideo: sampleVideo,
        videos: const [sampleVideo, _other],
      ),
      sampleEntry(id: 2, text: 'B', currentVideo: sampleVideo),
      sampleEntry(id: 3, text: 'C'),
    ]);
    await setPreferred(db, 1, _other);

    final rows = await getEntries(db, [1, 2, 3]);
    final videos = await preferredVideos(db, rows);

    expect(videos[1]?.id, _other.id);
    expect(videos[2]?.id, sampleVideo.id);
    expect(
      videos.containsKey(3),
      isFalse,
      reason: 'nothing to resolve without a video',
    );
  });
}
