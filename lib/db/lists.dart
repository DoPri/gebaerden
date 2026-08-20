import 'dart:math';

import 'package:drift/drift.dart';

import '../util/text.dart';
import 'database.dart';

const knownList = 'known';

const _system = [
  (id: knownList, name: 'Kenne ich schon', kind: ListKind.known),
  (id: 'favourites', name: 'Favoriten', kind: ListKind.favourites),
  (id: 'learning', name: 'Lernen', kind: ListKind.learning),
];

bool isSystem(StoredList list) => list.kind != ListKind.custom;

Future<void> ensureSystemLists(AppDatabase db) async {
  final now = DateTime.now();
  final have = (await db.select(db.lists).get()).map((l) => l.id).toSet();
  final missing = _system.where((s) => !have.contains(s.id));
  if (missing.isEmpty) return;

  await db.batch(
    (b) => b.insertAll(db.lists, [
      for (final s in missing)
        ListsCompanion.insert(
          id: s.id,
          name: s.name,
          kind: s.kind,
          createdAt: now,
          updatedAt: now,
        ),
    ]),
  );
}

Future<List<StoredList>> allLists(AppDatabase db) async {
  await ensureSystemLists(db);
  final lists = await db.select(db.lists).get();
  int rank(StoredList l) {
    final i = _system.indexWhere((s) => s.id == l.id);
    return i < 0 ? 99 : i;
  }

  lists.sort((a, b) {
    final ra = rank(a);
    final rb = rank(b);
    return ra != rb ? ra - rb : compareDe(a.name, b.name);
  });
  return lists;
}

final _random = Random.secure();

String _id() {
  final bytes = List.generate(16, (_) => _random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<StoredList> createList(AppDatabase db, String name) async {
  final now = DateTime.now();
  final list = StoredList(
    id: _id(),
    name: name.trim().isEmpty ? 'Neue Liste' : name.trim(),
    kind: ListKind.custom,
    createdAt: now,
    updatedAt: now,
  );
  await db.into(db.lists).insert(list);
  return list;
}

Future<void> renameList(AppDatabase db, String id, String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return;
  await (db.update(db.lists)..where((t) => t.id.equals(id))).write(
    ListsCompanion(name: Value(trimmed), updatedAt: Value(DateTime.now())),
  );
}

/// Null preserves existing limits; use [clearListLimits] to reset to global default.
Future<void> setListLimits(
  AppDatabase db,
  String id, {
  int? newPerDay,
  int? reviewPerDay,
}) async {
  await (db.update(db.lists)..where((t) => t.id.equals(id))).write(
    ListsCompanion(
      newPerDay: newPerDay == null ? const Value.absent() : Value(newPerDay),
      reviewPerDay: reviewPerDay == null
          ? const Value.absent()
          : Value(reviewPerDay),
      updatedAt: Value(DateTime.now()),
    ),
  );
}

Future<void> clearListLimits(AppDatabase db, String id) async {
  await (db.update(db.lists)..where((t) => t.id.equals(id))).write(
    ListsCompanion(
      newPerDay: const Value(null),
      reviewPerDay: const Value(null),
      updatedAt: Value(DateTime.now()),
    ),
  );
}

Future<void> deleteList(AppDatabase db, String id) async {
  final list = await (db.select(
    db.lists,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (list == null || isSystem(list)) return;
  await db.transaction(() async {
    await (db.delete(db.listItems)..where((t) => t.listId.equals(id))).go();
    // Cascade-delete list reminders.
    await (db.delete(db.reminders)..where((t) => t.listId.equals(id))).go();
    await (db.delete(db.lists)..where((t) => t.id.equals(id))).go();
  });
}

Future<StoredList?> duplicateList(
  AppDatabase db,
  String id,
  String name,
) async {
  final source = await (db.select(
    db.lists,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (source == null) return null;
  final copy = await createList(db, name);
  await addToList(db, copy.id, await listEntryIds(db, id));
  return copy;
}

Future<void> addToList(
  AppDatabase db,
  String listId,
  List<int> entryIds,
) async {
  if (entryIds.isEmpty) return;
  final base = DateTime.now();

  await db.transaction(() async {
    final existing = {
      for (final item
          in await (db.select(db.listItems)..where(
                (t) => t.listId.equals(listId) & t.entryId.isIn(entryIds),
              ))
              .get())
        item.entryId: item.addedAt,
    };

    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.listItems, [
        for (final (i, entryId) in entryIds.indexed)
          ListItemsCompanion.insert(
            listId: listId,
            entryId: entryId,
            // Stagger timestamps to preserve insertion order.
            addedAt: existing[entryId] ?? base.add(Duration(milliseconds: i)),
          ),
      ]),
    );
    await (db.update(db.lists)..where((t) => t.id.equals(listId))).write(
      ListsCompanion(updatedAt: Value(base)),
    );
  });
}

Future<void> removeFromList(
  AppDatabase db,
  String listId,
  List<int> entryIds,
) async {
  if (entryIds.isEmpty) return;
  await (db.delete(
    db.listItems,
  )..where((t) => t.listId.equals(listId) & t.entryId.isIn(entryIds))).go();
  await (db.update(db.lists)..where((t) => t.id.equals(listId))).write(
    ListsCompanion(updatedAt: Value(DateTime.now())),
  );
}

Future<bool> toggleInList(AppDatabase db, String listId, int entryId) async {
  final present =
      await (db.select(db.listItems)
            ..where((t) => t.listId.equals(listId) & t.entryId.equals(entryId)))
          .getSingleOrNull();
  if (present != null) {
    await removeFromList(db, listId, [entryId]);
    return false;
  }
  await addToList(db, listId, [entryId]);
  return true;
}

Future<List<int>> listEntryIds(AppDatabase db, String listId) async {
  final items =
      await (db.select(db.listItems)
            ..where((t) => t.listId.equals(listId))
            ..orderBy([(t) => OrderingTerm(expression: t.addedAt)]))
          .get();
  return items.map((i) => i.entryId).toList();
}

Future<Set<String>> listsContaining(AppDatabase db, int entryId) async {
  final items = await (db.select(
    db.listItems,
  )..where((t) => t.entryId.equals(entryId))).get();
  return items.map((i) => i.listId).toSet();
}

Future<Map<String, int>> listCounts(AppDatabase db) async {
  final count = db.listItems.entryId.count();
  final rows =
      await (db.selectOnly(db.listItems)
            ..addColumns([db.listItems.listId, count])
            ..groupBy([db.listItems.listId]))
          .get();
  return {
    for (final row in rows) row.read(db.listItems.listId)!: row.read(count)!,
  };
}
