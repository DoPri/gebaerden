import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/search/dictionary.dart';
import 'package:gebaerden/search/offline.dart';

import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = testDb();
    invalidateIndex();
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Haus', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Hausfrau', currentVideo: sampleVideo),
      sampleEntry(id: 3, text: 'Rathaus', currentVideo: sampleVideo),
      sampleEntry(id: 4, text: 'Bär', currentVideo: sampleVideo),
      sampleEntry(id: 5, text: 'Baum', currentVideo: sampleVideo),
      sampleEntry(id: 6, text: 'Fuß'),
    ]);
  });

  tearDown(() async {
    invalidateIndex();
    await db.close();
  });

  group('offline search', () {
    test('exact hit comes first', () async {
      final hits = await offlineSearch(db, 'Haus');
      expect(hits.first.word, 'Haus');
    });

    test('matches inside a word', () async {
      final hits = await offlineSearch(db, 'haus');
      expect(
        hits.map((e) => e.word),
        containsAll(['Haus', 'Hausfrau', 'Rathaus']),
      );
    });

    test('a rewritten umlaut finds the original', () async {
      expect(
        (await offlineSearch(db, 'Baer')).map((e) => e.word),
        contains('Bär'),
      );
      expect(
        (await offlineSearch(db, 'Fuss')).map((e) => e.word),
        contains('Fuß'),
      );
    });

    test('forgives a typo', () async {
      expect(
        (await offlineSearch(db, 'Baim')).map((e) => e.word),
        contains('Baum'),
      );
    });

    test('forgives two swapped letters', () async {
      // The most common typo of all, and it costs two plain edits.
      expect(
        (await offlineSearch(db, 'Huas')).map((e) => e.word),
        contains('Haus'),
      );
      expect(
        (await offlineSearch(db, 'Rathuas')).map((e) => e.word),
        contains('Rathaus'),
      );
    });

    test('forgives nothing on short input', () async {
      final hits = await offlineSearch(db, 'xyz');
      expect(hits, isEmpty);
    });

    test('blank input never touches the database', () async {
      expect(await offlineSearch(db, '   '), isEmpty);
    });

    test('honours the limit', () async {
      expect(await offlineSearch(db, 'haus', limit: 2), hasLength(2));
    });

    test('picks up newly cached entries', () async {
      expect(await offlineSearch(db, 'Katze'), isEmpty);
      await cacheEntries(db, [
        sampleEntry(id: 7, text: 'Katze', currentVideo: sampleVideo),
      ]);
      expect((await offlineSearch(db, 'Katze')).map((e) => e.word), ['Katze']);
    });

    test('picks up a word rewritten under a standing id', () async {
      // The row count never moves here, only the word does.
      expect((await offlineSearch(db, 'Haus')).first.word, 'Haus');
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Hausboot', currentVideo: sampleVideo),
      ]);

      expect((await offlineSearch(db, 'Hausboot')).map((e) => e.word), [
        'Hausboot',
      ]);
      expect(await db.select(db.entries).get(), hasLength(6));
    });
  });

  group('display order', () {
    test('exact before prefix before the rest', () async {
      final rows = await getEntries(db, [3, 2, 1]);
      expect(sortForDisplay(rows, 'Haus').map((e) => e.word), [
        'Haus',
        'Hausfrau',
        'Rathaus',
      ]);
    });
  });

  group('cached letter list', () {
    test('takes only the asked letter, alphabetically', () async {
      expect((await cachedLetter(db, 'B')).map((e) => e.word), ['Bär', 'Baum']);
    });
  });
}
