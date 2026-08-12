import 'package:drift/drift.dart';

import '../api/client.dart';
import '../api/queries.dart';
import '../db/database.dart';
import '../db/repo.dart';
import '../util/text.dart';
import 'offline.dart';

/// Shown while the request is in flight.
Future<List<CachedEntry>> cachedMatches(
  AppDatabase db,
  String query, {
  int limit = 60,
}) => offlineSearch(db, query, limit: limit);

Future<List<CachedEntry>> liveSearch(
  AppDatabase db,
  String query, {
  CancelToken? cancel,
}) async => cacheEntries(db, await searchWord(query, cancel: cancel));

Future<List<CachedEntry>> liveLetter(
  AppDatabase db,
  String letter, {
  CancelToken? cancel,
}) async => cacheEntries(db, await searchLetter(letter, cancel: cancel));

Future<List<CachedEntry>> cachedLetter(AppDatabase db, String letter) async {
  final rows = await (db.select(
    db.entries,
  )..where((t) => t.word.like('$letter%'))).get();
  rows.sort((a, b) => compareDe(a.word, b.word));
  return rows;
}

/// Exact match first, then prefix, then alphabetical.
List<CachedEntry> sortForDisplay(List<CachedEntry> rows, String query) {
  final q = query.trim().toLowerCase();
  int rank(CachedEntry e) {
    final t = e.word.toLowerCase();
    if (t == q) return 0;
    return t.startsWith(q) ? 1 : 2;
  }

  final sorted = [...rows]
    ..sort((a, b) {
      final ra = rank(a);
      final rb = rank(b);
      return ra != rb ? ra - rb : compareDe(a.word, b.word);
    });
  return sorted;
}

/// Substring search gives compounds for free: Haus finds Rathaus.
Future<List<CachedEntry>> relatedTo(
  AppDatabase db,
  CachedEntry entry, {
  int limit = 12,
}) async {
  final rows = await liveSearch(db, entry.word);
  return rows.where((r) => r.id != entry.id && r.hasVideo).take(limit).toList();
}
