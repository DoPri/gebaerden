import 'dart:convert';

import 'package:drift/drift.dart';

import '../api/queries.dart';
import '../db/database.dart';
import '../db/lists.dart';
import '../db/repo.dart';

const backupSchema = 'signdict-trainer/v2';

enum ImportMode { replace, merge }

enum BackupSection { lists, progress, settings, reminders }

const _sectionKeys = {
  BackupSection.lists: ['lists', 'listItems'],
  BackupSection.progress: ['cards', 'reviews'],
  BackupSection.settings: ['settings', 'variants'],
  BackupSection.reminders: ['reminders'],
};

Set<BackupSection> sectionsIn(String text) {
  final backup = _parse(text);
  return {
    for (final entry in _sectionKeys.entries)
      if (entry.value.any((k) => (backup[k] as List?)?.isNotEmpty ?? false))
        entry.key,
  };
}

class BackupError implements Exception {
  BackupError(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImportSummary {
  const ImportSummary({
    required this.cards,
    required this.reviews,
    required this.lists,
  });

  final int cards;
  final int reviews;
  final int lists;
}

// Default serializer rounds timestamps to ms, losing order precision.
final _exact = ValueSerializer.defaults(serializeDateTimeValuesAsString: true);

const backupExtension = 'dgsbackup';

// iOS file picker requires declared UTI in Info.plist.
const backupUti = 'gg.prinz.gebaerden.sicherung';

String backupFileName(DateTime at) =>
    'dgs-lernen-${at.toIso8601String().substring(0, 10)}.$backupExtension';

Future<String> exportBackup(
  AppDatabase db, {
  Set<BackupSection> sections = const {...BackupSection.values},
}) async {
  Future<List<Map<String, dynamic>>> rows<T extends DataClass>(
    BackupSection section,
    Future<List<T>> Function() read, {
    bool dropId = false,
  }) async {
    if (!sections.contains(section)) return const [];
    return [
      for (final row in await read())
        row.toJson(serializer: _exact)
          ..removeWhere((k, _) => dropId && k == 'id'),
    ];
  }

  return jsonEncode({
    'schema': backupSchema,
    'exportedAt': DateTime.now().toIso8601String(),
    'cards': await rows(BackupSection.progress, db.select(db.cards).get),
    // Device-local autoincrement ID would collide on import.
    'reviews': await rows(
      BackupSection.progress,
      db.select(db.reviews).get,
      dropId: true,
    ),
    'lists': await rows(BackupSection.lists, db.select(db.lists).get),
    'listItems': await rows(BackupSection.lists, db.select(db.listItems).get),
    'settings': await rows(BackupSection.settings, db.select(db.settings).get),
    'variants': await rows(BackupSection.settings, db.select(db.variants).get),
    'reminders': await rows(
      BackupSection.reminders,
      db.select(db.reminders).get,
      dropId: true,
    ),
  });
}

Map<String, dynamic> _parse(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } on FormatException {
    throw BackupError('Die Datei ist kein gültiges JSON.');
  }
  if (raw is! Map<String, dynamic>) {
    throw BackupError('Die Datei hat einen unerwarteten Inhalt.');
  }
  if (raw['schema'] != backupSchema) {
    throw BackupError('Das ist keine Sicherung dieser App.');
  }
  return raw;
}

List<T> _rows<T>(
  Map<String, dynamic> backup,
  String key,
  T Function(Map<String, dynamic>) build,
) {
  final raw = backup[key];
  if (raw == null) return [];
  if (raw is! List) throw BackupError('Der Abschnitt $key ist beschädigt.');
  try {
    return [for (final row in raw) build(row as Map<String, dynamic>)];
  } on Object {
    throw BackupError('Der Abschnitt $key ist beschädigt.');
  }
}

Future<ImportSummary> importBackup(
  AppDatabase db,
  String text,
  ImportMode mode, {
  Set<BackupSection> sections = const {...BackupSection.values},
}) async {
  final backup = _parse(text);
  bool want(BackupSection section) => sections.contains(section);

  final cards = _rows(
    backup,
    'cards',
    (r) => StoredCard.fromJson(r, serializer: _exact),
  );
  final reviews = _rows(
    backup,
    'reviews',
    (r) => StoredReview.fromJson({...r, 'id': 0}, serializer: _exact),
  );
  final lists = _rows(
    backup,
    'lists',
    (r) => StoredList.fromJson(r, serializer: _exact),
  );
  final items = _rows(
    backup,
    'listItems',
    (r) => StoredListItem.fromJson(r, serializer: _exact),
  );
  final settings = _rows(
    backup,
    'settings',
    (r) => StoredSetting.fromJson(r, serializer: _exact),
  );
  final variants = _rows(
    backup,
    'variants',
    (r) => StoredVariant.fromJson(r, serializer: _exact),
  );
  final reminders = _rows(
    backup,
    'reminders',
    (r) => StoredReminder.fromJson({...r, 'id': 0}, serializer: _exact),
  );

  await db.transaction(() async {
    if (mode == ImportMode.replace) {
      if (want(BackupSection.progress)) {
        await db.delete(db.reviews).go();
        await db.delete(db.cards).go();
      }
      if (want(BackupSection.lists)) {
        await db.delete(db.listItems).go();
        await db.delete(db.lists).go();
      }
      if (want(BackupSection.settings)) {
        await db.delete(db.variants).go();
        await db.delete(db.settings).go();
      }
      if (want(BackupSection.reminders)) await db.delete(db.reminders).go();
    }

    if (want(BackupSection.lists)) {
      await db.batch((b) {
        b.insertAllOnConflictUpdate(db.lists, lists);
        b.insertAllOnConflictUpdate(db.listItems, items);
      });
    }
    if (want(BackupSection.settings)) {
      await db.batch((b) {
        b.insertAllOnConflictUpdate(db.settings, settings);
        b.insertAllOnConflictUpdate(db.variants, variants);
      });
    }
    if (want(BackupSection.reminders)) {
      await _mergeReminders(db, reminders, mode);
    }
    if (want(BackupSection.progress)) {
      await _mergeCards(db, cards, mode);
      await _mergeReviews(db, reviews, mode);
    }
  });

  await ensureSystemLists(db);
  return ImportSummary(
    cards: cards.length,
    reviews: reviews.length,
    lists: lists.length,
  );
}

Future<void> _mergeCards(
  AppDatabase db,
  List<StoredCard> incoming,
  ImportMode mode,
) async {
  if (mode == ImportMode.replace) {
    await db.batch((b) => b.insertAllOnConflictUpdate(db.cards, incoming));
    return;
  }

  final local = {for (final c in await db.select(db.cards).get()) c.id: c};
  final winners = incoming.where((card) {
    final here = local[card.id];
    if (here == null) return true;
    // More reps wins; tie goes to later review.
    if (card.reps != here.reps) return card.reps > here.reps;
    final a = card.lastReview?.millisecondsSinceEpoch ?? 0;
    final b = here.lastReview?.millisecondsSinceEpoch ?? 0;
    return a > b;
  }).toList();
  await db.batch((b) => b.insertAllOnConflictUpdate(db.cards, winners));
}

String _reviewKey(StoredReview r) =>
    '${r.cardId}@${r.reviewedAt.microsecondsSinceEpoch}';

Future<void> _mergeReviews(
  AppDatabase db,
  List<StoredReview> incoming,
  ImportMode mode,
) async {
  var fresh = incoming;
  if (mode != ImportMode.replace) {
    final seen = (await db.select(db.reviews).get()).map(_reviewKey).toSet();
    fresh = incoming.where((r) => !seen.contains(_reviewKey(r))).toList();
  }

  await db.batch(
    (b) => b.insertAll(db.reviews, [
      for (final r in fresh)
        ReviewsCompanion.insert(
          cardId: r.cardId,
          entryId: r.entryId,
          rating: r.rating,
          reviewedAt: r.reviewedAt,
          before: r.before,
        ),
    ]),
  );
}

// Composite key deduplicates reminders since IDs are omitted on export.
String _reminderKey(StoredReminder r) =>
    '${r.listId}@${r.days}@${r.hour}:${r.minute}';

Future<void> _mergeReminders(
  AppDatabase db,
  List<StoredReminder> incoming,
  ImportMode mode,
) async {
  var fresh = incoming;
  if (mode != ImportMode.replace) {
    final seen = (await db.select(db.reminders).get())
        .map(_reminderKey)
        .toSet();
    fresh = incoming.where((r) => !seen.contains(_reminderKey(r))).toList();
  }

  await db.batch(
    (b) => b.insertAll(db.reminders, [
      for (final r in fresh)
        RemindersCompanion.insert(
          listId: r.listId,
          days: r.days,
          hour: r.hour,
          minute: r.minute,
        ),
    ]),
  );
}

Future<List<int>> missingEntryIds(AppDatabase db) async {
  final wanted = <int>{
    ...(await db.select(db.cards).get()).map((c) => c.entryId),
    ...(await db.select(db.listItems).get()).map((i) => i.entryId),
  };
  if (wanted.isEmpty) return [];

  final have = (await (db.select(
    db.entries,
  )..where((t) => t.id.isIn(wanted))).get()).map((e) => e.id).toSet();
  return wanted.where((id) => !have.contains(id)).toList();
}

// Limit GraphQL query size per request.
const _chunk = 100;

Future<int> restoreEntries(AppDatabase db) async {
  final missing = await missingEntryIds(db);
  for (var i = 0; i < missing.length; i += _chunk) {
    final slice = missing.sublist(i, (i + _chunk).clamp(0, missing.length));
    await cacheEntries(db, await fetchEntries(slice));
  }
  return missing.length;
}
