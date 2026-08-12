import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/search/corpus.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'harness.dart';
import 'support.dart';

Map<String, dynamic> _entry(int id, String text) => {
  'id': id,
  'text': text,
  'currentVideo': sampleVideo.toJson(),
};

/// Serves [pages] pages and then an empty one, the way the real index ends.
void _stubIndex({int pages = 2, int per = 2, int firstId = 100}) {
  _stubbed = 0;
  stubPer((body) {
    _stubbed++;
    final page = int.parse(RegExp(r'"page":(\d+)').firstMatch(body)!.group(1)!);
    return {
      'index': page <= pages
          ? [
              for (var i = 0; i < per; i++)
                _entry(firstId + (page - 1) * per + i, 'Wort $page-$i'),
            ]
          : <Object>[],
    };
  });
}

int _stubbed = 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = testDb());

  tearDown(() async {
    useClient(http.Client());
    await db.close();
  });

  test('the walk writes the whole index into the cache', () async {
    _stubIndex(pages: 3, per: 2);

    expect(await syncDictionary(db), 6);
    expect(await db.select(db.entries).get(), hasLength(6));
    // Three pages of entries plus the empty one that ends it.
    expect(_stubbed, 4);
  });

  test('the trainer counts the corpus once it is there', () async {
    // The whole bug: the deck is drawn from the entry cache and nothing ever
    // filled it, so a fresh install opened Lernen on zero and zero.
    expect((await buildDeck(db)).newCount, 0);

    _stubIndex(pages: 2, per: 3);
    await syncDictionary(db);

    expect((await buildDeck(db)).newCount, 6);
  });

  test('a second start does not walk the index again', () async {
    _stubIndex();
    expect(await syncDictionaryOnce(db), isTrue);

    useClient(MockClient((_) async => throw StateError('darf nicht rufen')));
    expect(await syncDictionaryOnce(db), isTrue);
  });

  test('a walk that failed is tried again next start', () async {
    stubApiFailure();

    expect(await syncDictionaryOnce(db), isFalse);
    // Nothing was remembered, otherwise one flight without net would cost the
    // trainer its corpus for good.
    expect(await dictionarySynced(db), isFalse);

    _stubIndex();
    expect(await syncDictionaryOnce(db), isTrue);
    expect(await dictionarySynced(db), isTrue);
  });

  test('a cache that only saw a browsed word still gets the rest', () async {
    await cacheEntries(db, [sampleEntry(id: 1, text: 'Hallo')]);
    // Not empty is not the same as complete: counting rows would call this
    // done and leave the trainer with the one word that was looked up.
    expect(await dictionarySynced(db), isFalse);

    _stubIndex(pages: 2, per: 2);
    expect(await syncDictionaryOnce(db), isTrue);

    expect(await db.select(db.entries).get(), hasLength(5));
  });
}
