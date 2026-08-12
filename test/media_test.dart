import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/media/media.dart';
import 'package:gebaerden/media/variants.dart';

import 'support.dart';

const _other = ApiVideo(
  id: 4711,
  videoUrl: 'https://example.invalid/other.mp4',
  thumbnailUrl: 'https://example.invalid/other.jpg',
);

void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() {
    db = testDb();
    tmp = Directory.systemTemp.createTempSync('media_test');
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<String> onDisk(String name) async {
    final file = File('${tmp.path}/$name')..writeAsStringSync('x');
    return file.path;
  }

  Future<void> store(int videoId, AssetKind kind, int entryId, String path) {
    return db
        .into(db.assets)
        .insertOnConflictUpdate(
          StoredAsset(
            videoId: videoId,
            kind: kind,
            entryId: entryId,
            localPath: path,
            bytes: 1,
            downloadedAt: DateTime.now(),
          ),
        );
  }

  group('resolveMedia', () {
    test('nothing to resolve without a video', () async {
      expect(await resolveMedia(db, null, AssetKind.video), isNull);
    });

    test('falls back to the CDN', () async {
      final source = await resolveMedia(db, sampleVideo, AssetKind.video);
      expect(source!.isFile, isFalse);
      expect(source.url, sampleVideo.videoUrl);
    });

    test('the local copy wins', () async {
      final path = await onDisk('951.mp4');
      await store(sampleVideo.id, AssetKind.video, 1, path);

      final source = await resolveMedia(db, sampleVideo, AssetKind.video);
      expect(source!.isFile, isTrue);
      expect(source.path, path);
    });

    test('a row without its file falls back instead of breaking', () async {
      await store(sampleVideo.id, AssetKind.video, 1, '${tmp.path}/weg.mp4');

      final source = await resolveMedia(db, sampleVideo, AssetKind.video);
      expect(source!.isFile, isFalse);
      expect(source.url, sampleVideo.videoUrl);
    });

    test('video and thumbnail are kept apart', () async {
      final path = await onDisk('951.jpg');
      await store(sampleVideo.id, AssetKind.thumbnail, 1, path);

      expect(
        (await resolveMedia(db, sampleVideo, AssetKind.thumbnail))!.isFile,
        isTrue,
      );
      expect(
        (await resolveMedia(db, sampleVideo, AssetKind.video))!.isFile,
        isFalse,
      );
    });

    test('no url and no file means nothing at all', () async {
      const bare = ApiVideo(id: 99);
      expect(await resolveMedia(db, bare, AssetKind.video), isNull);
    });
  });

  group('thumbnailsFor', () {
    test('follows the picked variant', () async {
      final rows = await cacheEntries(db, [
        sampleEntry(
          currentVideo: sampleVideo,
          videos: const [sampleVideo, _other],
        ),
      ]);
      await setPreferred(db, rows.single.id, _other);

      final thumbs = await thumbnailsFor(db, rows);
      expect(thumbs[rows.single.id]!.url, _other.thumbnailUrl);
    });

    test('skips entries without any video', () async {
      final rows = await cacheEntries(db, [sampleEntry(id: 5, text: 'Leer')]);
      expect(await thumbnailsFor(db, rows), isEmpty);
    });

    test('an empty list asks the database nothing', () async {
      expect(await thumbnailsFor(db, []), isEmpty);
    });
  });
}
