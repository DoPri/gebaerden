@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/queries.dart';

/// Runs against signdict.org. There is no bundled dictionary, so a broken
/// endpoint has to fail here, not on a phone.
void main() {
  test('searchWord finds a common word', () async {
    final hits = await searchWord('Haus');
    expect(hits, isNotEmpty);
    expect(hits.any((e) => e.text.toLowerCase() == 'haus'), isTrue);
  });

  test('searchWord on blank input skips the network', () async {
    expect(await searchWord('   '), isEmpty);
  });

  test('fetchEntry carries variants the list query does not', () async {
    final hits = await searchWord('Haus');
    final listed = hits.firstWhere((e) => e.text.toLowerCase() == 'haus');
    expect(listed.videos, isNull, reason: 'list query carries no variants');

    final full = await fetchEntry(listed.id);
    expect(full, isNotNull);
    expect(full!.videos, isNotNull);
    expect(full.currentVideo?.videoUrl, isNotNull);
  });

  test('searchLetter drops the umlaut folding', () async {
    final hits = await searchLetter('A');
    expect(hits, isNotEmpty);
    expect(hits.every((e) => e.text.toUpperCase().startsWith('A')), isTrue);
  });

  test('fetchEntries takes many ids in one round trip', () async {
    final ids = (await searchLetter('B')).take(5).map((e) => e.id).toList();
    final rows = await fetchEntries(ids);
    expect(rows.map((e) => e.id), containsAll(ids));
  });

  test('resolveExact maps words to ids', () async {
    final found = await resolveExact(['Haus', 'Baum']);
    expect(found.keys, containsAll(['Haus', 'Baum']));
  });

  test('index returns full pages', () async {
    final page = await fetchIndexPage(1);
    expect(page, hasLength(pageSize));
  });

  test('unknown id returns null instead of throwing', () async {
    expect(await fetchEntry(99999999), isNull);
  });
}
