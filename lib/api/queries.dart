import 'dart:convert';
import 'dart:math';

import 'client.dart';
import 'types.dart';

/// Upstream API limit.
const pageSize = 100;

const letters = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

/// Initial estimate of total index pages.
const indexPages = 53;

const _videoFields = '''
  id videoUrl thumbnailUrl license copyright originalHref updatedAt user { name }
''';

const _listFields =
    '''
  id text type description
  language { shortName }
  currentVideo { $_videoFields }
''';

const _detailFields =
    '''
  $_listFields
  videos { $_videoFields }
''';

List<ApiEntry> _entries(Object? raw) => (raw as List? ?? [])
    .map((e) => ApiEntry.fromJson(e as Map<String, dynamic>))
    .toList();

Future<List<ApiEntry>> searchWord(String word, {CancelToken? cancel}) async {
  final trimmed = word.trim();
  if (trimmed.isEmpty) return [];
  final data = await gql(
    'query Search(\$word: String!) { search(word: \$word) { $_listFields } }',
    variables: {'word': trimmed},
    cancel: cancel,
  );
  return _entries(data['search']);
}

/// Upstream folds umlauts onto base vowels.
Future<List<ApiEntry>> searchLetter(
  String letter, {
  CancelToken? cancel,
}) async {
  final upper = letter.toUpperCase();
  final data = await gql(
    'query Letter(\$letter: String!) { search(letter: \$letter) { $_listFields } }',
    variables: {'letter': upper},
    cancel: cancel,
  );
  return _entries(data['search'])
      .where((e) => e.text.isNotEmpty && e.text[0].toUpperCase() == upper)
      .toList();
}

Future<ApiEntry?> fetchEntry(int id, {CancelToken? cancel}) async {
  try {
    final data = await gql(
      'query Entry(\$id: ID!) { entry(id: \$id) { $_detailFields } }',
      variables: {'id': '$id'},
      cancel: cancel,
    );
    final entry = data['entry'] as Map<String, dynamic>?;
    return entry == null ? null : ApiEntry.fromJson(entry);
  } on GraphqlError catch (err) {
    // Missing entries return null instead of throwing.
    if (err.notFound) return null;
    rethrow;
  }
}

Future<List<ApiEntry>> fetchEntries(
  List<int> ids, {
  CancelToken? cancel,
}) async {
  if (ids.isEmpty) return [];
  final fields = [
    for (var i = 0; i < ids.length; i++)
      'e$i: entry(id: ${ids[i]}) { $_listFields }',
  ].join(' ');
  final data = await gql('query { $fields }', cancel: cancel);
  return [
    for (var i = 0; i < ids.length; i++)
      if (data['e$i'] != null)
        ApiEntry.fromJson(data['e$i'] as Map<String, dynamic>),
  ];
}

/// Requests minimal fields to avoid oversized responses on substring matches.
Future<Map<String, int>> resolveExact(
  List<String> words, {
  CancelToken? cancel,
}) async {
  if (words.isEmpty) return {};
  final fields = [
    for (var i = 0; i < words.length; i++)
      'w$i: search(word: ${jsonEncode(words[i])}) { id text }',
  ].join(' ');
  final data = await gql('query { $fields }', cancel: cancel);

  final found = <String, int>{};
  for (var i = 0; i < words.length; i++) {
    final hits = (data['w$i'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final hit in hits) {
      if ((hit['text'] as String).toLowerCase() == words[i].toLowerCase()) {
        found[words[i]] = hit['id'] as int;
        break;
      }
    }
  }
  return found;
}

Future<List<ApiEntry>> fetchIndexPage(int page, {CancelToken? cancel}) async {
  final data = await gql(
    'query Index(\$page: Int!, \$perPage: Int!) '
    '{ index(page: \$page, perPage: \$perPage) { $_listFields } }',
    variables: {'page': page, 'perPage': pageSize},
    cancel: cancel,
  );
  return _entries(data['index']);
}

/// Letter search misses ~600 entries upstream.
Stream<List<ApiEntry>> iterateIndex({CancelToken? cancel}) async* {
  for (var page = 1; ; page++) {
    final batch = await fetchIndexPage(page, cancel: cancel);
    if (batch.isEmpty) return;
    yield batch;
  }
}

Future<int> lastIndexPage({int hint = indexPages, CancelToken? cancel}) async {
  var page = max(1, hint);

  if ((await fetchIndexPage(page, cancel: cancel)).isEmpty) {
    while (page > 1) {
      page--;
      if ((await fetchIndexPage(page, cancel: cancel)).isNotEmpty) return page;
    }
    return 1;
  }

  while ((await fetchIndexPage(page + 1, cancel: cancel)).isNotEmpty) {
    page++;
  }
  return page;
}

final _random = Random();

Future<ApiEntry?> randomEntry({CancelToken? cancel}) async {
  final page = 1 + _random.nextInt(indexPages);
  final withVideo = (await fetchIndexPage(
    page,
    cancel: cancel,
  )).where((e) => e.currentVideo?.videoUrl != null).toList();
  return withVideo.isEmpty
      ? null
      : withVideo[_random.nextInt(withVideo.length)];
}
