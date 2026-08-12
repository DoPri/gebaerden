import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/srs/charset.dart';
import 'package:http/http.dart' as http;

import 'harness.dart';
import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  Future<Map<String, CachedEntry>> handshapes(List<String> chars) async {
    final rows = await cacheEntries(db, [
      for (final (i, c) in chars.indexed)
        sampleEntry(id: 1000 + i, text: c, currentVideo: sampleVideo),
    ]);
    return {for (final (i, c) in chars.indexed) c: rows[i]};
  }

  group('character sets', () {
    test('the alphabet carries the umlauts and the two digraphs', () {
      final chars = charactersOf(Charset.alphabet);
      expect(chars, hasLength(31));
      expect(chars, containsAll(['a', 'z', 'ä', 'ö', 'ü', 'sch', 'ch']));
    });

    test('numbers run from zero to twenty', () {
      final chars = charactersOf(Charset.numbers);
      expect(chars, hasLength(21));
      expect(chars.first, '0');
      expect(chars.last, '20');
    });
  });

  group('splitting a word', () {
    test('one letter at a time', () async {
      final set = await handshapes(['h', 'a', 'u', 's']);
      expect(toChars('Haus', set), ['h', 'a', 'u', 's']);
    });

    test('sch beats s plus c plus h', () async {
      final set = await handshapes(['s', 'c', 'h', 'u', 'l', 'e']);
      expect(toChars('Schule', set), ['s', 'c', 'h', 'u', 'l', 'e']);

      final withDigraph = await handshapes([
        's',
        'c',
        'h',
        'u',
        'l',
        'e',
        'sch',
      ]);
      expect(toChars('Schule', withDigraph), ['sch', 'u', 'l', 'e']);
    });

    test('ch is taken as one shape too', () async {
      final set = await handshapes(['b', 'u', 'c', 'h', 'ch']);
      expect(toChars('Buch', set), ['b', 'u', 'ch']);
    });

    test('a missing letter makes the word unspellable', () async {
      final set = await handshapes(['h', 'a', 'u']);
      expect(toChars('Haus', set), isNull);
    });
  });

  group('spellable words', () {
    test('only what the set can spell, and only short words', () async {
      final set = await handshapes(['h', 'a', 'u', 's', 'm']);
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Haus', currentVideo: sampleVideo),
        sampleEntry(id: 2, text: 'Maus', currentVideo: sampleVideo),
        // Too long.
        sampleEntry(id: 3, text: 'Haushaltsplan', currentVideo: sampleVideo),
        // Letters the set does not hold.
        sampleEntry(id: 4, text: 'Zug', currentVideo: sampleVideo),
        // No video.
        sampleEntry(id: 5, text: 'Saum'),
      ]);

      final words = await spellableWords(db, set);
      expect(words, containsAll(['Haus', 'Maus']));
      expect(words, isNot(contains('Haushaltsplan')));
      expect(words, isNot(contains('Zug')));
      expect(words, isNot(contains('Saum')));
    });
  });

  test('pick returns something from the list', () {
    expect([1, 2, 3], contains(pick([1, 2, 3])));
  });

  group('stored mapping', () {
    tearDown(() => useClient(http.Client()));

    test('a mapping with wrong types is resolved again', () async {
      // An imported backup can carry anything under this key.
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            const StoredSetting(key: 'charset:numbers', value: {'1': 'eins'}),
          );
      stubEcho();

      final set = await loadCharset(db, Charset.numbers);
      expect(set.keys, contains('1'));

      final row = await (db.select(
        db.settings,
      )..where((t) => t.key.equals('charset:numbers'))).getSingle();
      expect((row.value! as Map).values, everyElement(isA<int>()));
    });
  });
}
