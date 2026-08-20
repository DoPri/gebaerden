import 'dart:math';

import '../api/queries.dart';
import '../db/database.dart';
import '../db/repo.dart';

enum Charset { alphabet, numbers }

const _alphabet = [
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', //
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  'ä', 'ö', 'ü', 'sch', 'ch',
];

List<String> charactersOf(Charset set) =>
    set == Charset.alphabet ? _alphabet : [for (var i = 0; i <= 20; i++) '$i'];

final _random = Random();

T pick<T>(List<T> items) => items[_random.nextInt(items.length)];

/// Resolving characters costs 52 API queries, so mapping is cached in settings.
Future<Map<String, CachedEntry>> loadCharset(
  AppDatabase db,
  Charset set,
) async {
  final key = 'charset:${set.name}';
  final stored = await (db.select(
    db.settings,
  )..where((t) => t.key.equals(key))).getSingleOrNull();

  var ids = <String, int>{};
  final storedIds = stored?.value;
  // Imported backups may be malformed; re-resolve if structure is invalid.
  if (storedIds is Map && storedIds.values.every((v) => v is int)) {
    ids = storedIds.map((k, v) => MapEntry('$k', v as int));
  } else {
    ids = await resolveExact(charactersOf(set));
    await db
        .into(db.settings)
        .insertOnConflictUpdate(StoredSetting(key: key, value: ids));
  }

  var rows = await getEntries(db, ids.values.toList());
  if (rows.length < ids.length) {
    rows = await cacheEntries(db, await fetchEntries(ids.values.toList()));
  }

  final byId = {for (final row in rows) row.id: row};
  final resolved = <String, CachedEntry>{};
  for (final entry in ids.entries) {
    final row = byId[entry.value];
    if (row != null && row.hasVideo) resolved[entry.key] = row;
  }
  return resolved;
}

/// Splits words prioritizing longer multi-letter handshapes (e.g. 'sch' before 's').
List<String>? toChars(String word, Map<String, CachedEntry> set) {
  final lower = word.toLowerCase();
  final multi = set.keys.where((c) => c.length > 1).toList()
    ..sort((a, b) => b.length - a.length);

  final out = <String>[];
  var i = 0;
  while (i < lower.length) {
    final match = multi.firstWhere(
      (c) => lower.startsWith(c, i),
      orElse: () => lower[i],
    );
    if (!set.containsKey(match)) return null;
    out.add(match);
    i += match.length;
  }
  return out;
}

final _spellable = RegExp(r'^[a-zäöüß]{3,6}$');

/// Filters local cache for words spellable with available charset handshapes.
Future<List<String>> spellableWords(
  AppDatabase db,
  Map<String, CachedEntry> set,
) async {
  final rows =
      await (db.select(db.entries)
            ..where((t) => t.hasVideo.equals(true))
            ..limit(600))
          .get();

  return rows
      .map((r) => r.word)
      .where(
        (w) => _spellable.hasMatch(w.toLowerCase()) && toChars(w, set) != null,
      )
      .toList();
}
