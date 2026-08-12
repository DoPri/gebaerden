import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/api/queries.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'harness.dart';
import 'support.dart';

Map<String, dynamic> _entry(int id, String text, {bool video = true}) => {
  'id': id,
  'text': text,
  if (video) 'currentVideo': sampleVideo.toJson(),
};

void main() {
  tearDown(() => useClient(http.Client()));

  test('fetchEntries maps the aliases back in order', () async {
    stubPer(
      (_) => {
        'e0': _entry(1, 'A'),
        'e1': _entry(2, 'B'),
        'e2': null,
        'e3': _entry(4, 'D'),
      },
    );

    final rows = await fetchEntries([1, 2, 3, 4]);
    expect(rows.map((e) => e.id), [1, 2, 4]);
  });

  test('fetchEntries on an empty list skips the round trip', () async {
    useClient(MockClient((_) async => throw StateError('darf nicht rufen')));
    expect(await fetchEntries([]), isEmpty);
  });

  test('resolveExact only takes an exact match', () async {
    stubPer(
      (_) => {
        'w0': [
          {'id': 1, 'text': 'Hausfrau'},
          {'id': 2, 'text': 'Haus'},
        ],
        'w1': [
          {'id': 3, 'text': 'Baumhaus'},
        ],
      },
    );

    final found = await resolveExact(['Haus', 'Baum']);
    expect(found, {'Haus': 2});
  });

  test('resolveExact on an empty list skips the round trip', () async {
    useClient(MockClient((_) async => throw StateError('darf nicht rufen')));
    expect(await resolveExact([]), isEmpty);
  });

  test('iterateIndex walks until a page comes back empty', () async {
    var page = 0;
    stubPer((_) {
      page++;
      return {
        'index': page <= 2 ? [_entry(page, 'Seite $page')] : <Object>[],
      };
    });

    final batches = await iterateIndex().toList();
    expect(batches, hasLength(2));
    expect(page, 3);
  });

  test('lastIndexPage walks forward from a low hint', () async {
    stubPer((body) {
      final at = RegExp(r'"page":(\d+)').firstMatch(body)!.group(1)!;
      return {
        'index': int.parse(at) <= 5 ? [_entry(1, 'x')] : <Object>[],
      };
    });

    expect(await lastIndexPage(hint: 2), 5);
  });

  test('lastIndexPage walks back from a hint past the end', () async {
    stubPer((body) {
      final at = RegExp(r'"page":(\d+)').firstMatch(body)!.group(1)!;
      return {
        'index': int.parse(at) <= 3 ? [_entry(1, 'x')] : <Object>[],
      };
    });

    expect(await lastIndexPage(hint: 40), 3);
  });

  test('lastIndexPage lands on one when nothing is there', () async {
    stubPer((_) => {'index': <Object>[]});
    expect(await lastIndexPage(hint: 3), 1);
  });

  test('randomEntry only returns something playable', () async {
    stubPer(
      (_) => {
        'index': [_entry(1, 'Ohne', video: false), _entry(2, 'Mit')],
      },
    );

    final entry = await randomEntry();
    expect(entry!.id, 2);
  });

  test('randomEntry gives null when the page has no videos', () async {
    stubPer(
      (_) => {
        'index': [_entry(1, 'Ohne', video: false)],
      },
    );
    expect(await randomEntry(), isNull);
  });

  test('searchLetter throws away the umlaut folding', () async {
    stubPer(
      (_) => {
        'search': [_entry(1, 'Apfel'), _entry(2, 'Ärger'), _entry(3, 'Auto')],
      },
    );

    final hits = await searchLetter('a');
    expect(hits.map((e) => e.text), ['Apfel', 'Auto']);
  });

  test('a cancelled search never reaches the wire', () async {
    useClient(MockClient((_) async => throw StateError('darf nicht rufen')));
    final cancel = CancelToken()..cancel();
    await expectLater(
      searchWord('Haus', cancel: cancel),
      throwsA(isA<Cancelled>()),
    );
  });
}
