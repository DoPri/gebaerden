import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/search/latest.dart';
import 'package:http/http.dart' as http;

import 'harness.dart';
import 'support.dart';

/// Stubs paginated index API with trailing video-less entries.
void stubIndex(int last, {int perPage = 3}) {
  stubPer((body) {
    final page = int.parse(RegExp(r'"page":(\d+)').firstMatch(body)!.group(1)!);
    if (page > last) return {'index': <Object>[]};
    return {
      'index': [
        for (var i = 0; i < perPage; i++)
          {
            'id': page * 100 + i,
            'text': 'Wort $page-$i',
            if (page != last) 'currentVideo': sampleVideo.toJson(),
          },
      ],
    };
  });
}

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() async {
    useClient(http.Client());
    await db.close();
  });

  test('walks back from the last page and puts the newest first', () async {
    stubIndex(4);
    final rows = await newestEntries(db, limit: 5);

    expect(rows, hasLength(5));
    expect(rows.first.word, 'Wort 3-2');
    expect(rows.every((r) => r.hasVideo), isTrue);
  });

  test('remembers where the index ended', () async {
    stubIndex(4);
    await newestEntries(db, limit: 1);

    final hint = await (db.select(
      db.settings,
    )..where((t) => t.key.equals('index:lastPage'))).getSingle();
    expect(hint.value, 4);
  });

  test('the second run starts from the remembered page', () async {
    stubIndex(4);
    await newestEntries(db, limit: 1);

    var pages = <int>[];
    stubPer((body) {
      final page = int.parse(
        RegExp(r'"page":(\d+)').firstMatch(body)!.group(1)!,
      );
      pages.add(page);
      return {
        'index': page > 4
            ? <Object>[]
            : [
                {
                  'id': page,
                  'text': 'Wort $page',
                  'currentVideo': sampleVideo.toJson(),
                },
              ],
      };
    });

    await newestEntries(db, limit: 1);
    expect(pages.first, 4);
    pages = [];
  });

  test('an empty index gives nothing back', () async {
    stubPer((_) => {'index': <Object>[]});
    expect(await newestEntries(db), isEmpty);
  });
}
