import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';

import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  test('marks entries with playable footage', () async {
    final rows = await cacheEntries(db, [
      sampleEntry(currentVideo: sampleVideo),
      sampleEntry(id: 836, text: 'Example sentence'),
    ]);
    expect(rows.firstWhere((r) => r.id == 835).hasVideo, isTrue);
    expect(rows.firstWhere((r) => r.id == 836).hasVideo, isFalse);
  });

  test('falls back to the first video when currentVideo is absent', () async {
    final rows = await cacheEntries(db, [
      sampleEntry(videos: const [sampleVideo]),
    ]);
    expect(rows.single.currentVideo?.id, sampleVideo.id);
    expect(rows.single.hasVideo, isTrue);
  });

  test('treats a blank description as absent', () async {
    final rows = await cacheEntries(db, [sampleEntry(description: '   ')]);
    expect(rows.single.description, isNull);
  });

  test('a list response does not drop the detail variants', () async {
    await cacheEntries(db, [
      sampleEntry(currentVideo: sampleVideo, videos: const [sampleVideo]),
    ]);
    await cacheEntries(db, [sampleEntry(currentVideo: sampleVideo)]);

    final row = await getEntry(db, 835);
    expect(row?.videos, hasLength(1));
  });

  test('getEntries keeps the requested order', () async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'A'),
      sampleEntry(id: 2, text: 'B'),
      sampleEntry(id: 3, text: 'C'),
    ]);
    expect((await getEntries(db, [3, 1, 2])).map((e) => e.id), [3, 1, 2]);
  });

  test('getEntries skips what is not cached', () async {
    await cacheEntries(db, [sampleEntry(id: 1, text: 'A')]);
    expect((await getEntries(db, [1, 99])).map((e) => e.id), [1]);
  });
}
