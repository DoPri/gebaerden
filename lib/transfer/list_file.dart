import 'dart:convert';

import '../api/queries.dart';
import '../db/database.dart';
import '../db/lists.dart';
import '../db/repo.dart';

const listSchema = 'signdict-liste/v1';
const listExtension = 'dgsliste';

// iOS file picker requires declared UTI in Info.plist.
const listUti = 'gg.prinz.gebaerden.liste';

class SharedList {
  const SharedList(this.name, this.entries);

  final String name;

  // Inlined word avoids immediate network lookup on import.
  final List<({int id, String word})> entries;
}

class ListFileError implements Exception {
  ListFileError(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<String> encodeList(AppDatabase db, StoredList list) async {
  final entries = await getEntries(db, await listEntryIds(db, list.id));
  return jsonEncode({
    'schema': listSchema,
    'name': list.name,
    'entries': [
      for (final entry in entries) {'id': entry.id, 'text': entry.word},
    ],
  });
}

SharedList parseListFile(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } on FormatException {
    throw ListFileError('Die Datei ist kein gültiges JSON.');
  }

  if (raw is! Map<String, dynamic>) {
    throw ListFileError('Die Datei hat einen unerwarteten Aufbau.');
  }
  if (raw['schema'] != listSchema) {
    throw ListFileError('Das ist keine Gebärden-Liste.');
  }

  final name = raw['name'];
  final entries = raw['entries'];
  if (name is! String || entries is! List) {
    throw ListFileError('Die Datei ist unvollständig.');
  }

  final parsed = <({int id, String word})>[];
  for (final item in entries) {
    if (item is! Map || item['id'] is! int || item['text'] is! String) {
      throw ListFileError('Ein Eintrag in der Datei ist beschädigt.');
    }
    parsed.add((id: item['id'] as int, word: item['text'] as String));
  }
  return SharedList(
    name.trim().isEmpty ? 'Geteilte Liste' : name.trim(),
    parsed,
  );
}

String listFileName(String name) {
  // Strip invalid filename characters without removing umlauts.
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  return '${safe.isEmpty ? 'Liste' : safe}.$listExtension';
}

Future<StoredList> importSharedList(AppDatabase db, SharedList shared) async {
  final list = await createList(db, shared.name);
  await addToList(db, list.id, shared.entries.map((e) => e.id).toList());

  final known = (await getEntries(
    db,
    shared.entries.map((e) => e.id).toList(),
  )).map((e) => e.id).toSet();
  final missing = shared.entries
      .where((e) => !known.contains(e.id))
      .map((e) => e.id)
      .toList();

  for (var i = 0; i < missing.length; i += 100) {
    final chunk = missing.sublist(i, (i + 100).clamp(0, missing.length));
    try {
      await cacheEntries(db, await fetchEntries(chunk));
    } on Exception {
      // Missing metadata can be lazily fetched when online.
      break;
    }
  }
  return list;
}
