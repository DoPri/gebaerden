import 'dart:math';

import '../db/database.dart';
import '../db/repo.dart';
import '../util/text.dart';

class _Indexed {
  const _Indexed(this.id, this.word, this.folded);

  final int id;
  final String word;
  final String folded;
}

List<_Indexed>? _index;
AppDatabase? _indexed;
int? _stamp;

// Rebuilds search cache on entriesRevision or database instance changes.
Future<List<_Indexed>> _ensureIndex(AppDatabase db) async {
  final current = _index;
  if (current != null && identical(_indexed, db) && _stamp == entriesRevision) {
    return current;
  }

  final rows = await (db.selectOnly(
    db.entries,
  )..addColumns([db.entries.id, db.entries.word])).get();

  final next = [
    for (final row in rows)
      _Indexed(
        row.read(db.entries.id)!,
        row.read(db.entries.word)!,
        normalizeAnswer(row.read(db.entries.word)!),
      ),
  ];

  _index = next;
  _indexed = db;
  _stamp = entriesRevision;
  return next;
}

void invalidateIndex() {
  _index = null;
  _indexed = null;
  _stamp = null;
}

int _distance(String a, String b, int budget) {
  if ((a.length - b.length).abs() > budget) return budget + 1;

  var older = <int>[];
  var previous = List<int>.generate(b.length + 1, (i) => i);
  final current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    var best = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var step = min(
        min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );

      // Treats adjacent transposition as a single edit (Damerau-Levenshtein).
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        step = min(step, older[j - 2] + 1);
      }

      current[j] = step;
      best = min(best, step);
    }
    if (best > budget) return budget + 1;
    older = previous;
    previous = List<int>.from(current);
  }
  return previous[b.length];
}

// Performs in-memory scan over full corpus to support typo-tolerant matching.
Future<List<CachedEntry>> offlineSearch(
  AppDatabase db,
  String query, {
  int limit = 60,
}) async {
  final folded = normalizeAnswer(query);
  if (folded.isEmpty) return [];

  final index = await _ensureIndex(db);
  final budget = folded.length < 4 ? 0 : min(2, folded.length ~/ 4);

  final scored = <(int, String, int)>[];
  for (final row in index) {
    int rank;
    if (row.folded == folded) {
      rank = 0;
    } else if (row.folded.startsWith(folded)) {
      rank = 1;
    } else if (row.folded.contains(folded)) {
      rank = 2;
    } else if (budget > 0 && _distance(row.folded, folded, budget) <= budget) {
      rank = 3;
    } else {
      continue;
    }
    scored.add((rank, row.word, row.id));
  }

  scored.sort((a, b) {
    if (a.$1 != b.$1) return a.$1 - b.$1;
    if (a.$2.length != b.$2.length) return a.$2.length - b.$2.length;
    return compareDe(a.$2, b.$2);
  });

  return getEntries(db, [for (final hit in scored.take(limit)) hit.$3]);
}
