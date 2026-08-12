import 'package:drift/drift.dart';

import 'database.dart';

const _keep = 20;

Future<void> remember(
  AppDatabase db,
  RecentKind kind,
  String value,
  String label,
) async {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return;

  await db.transaction(() async {
    await (db.delete(
      db.recents,
    )..where((t) => t.kind.equalsValue(kind) & t.value.equals(trimmed))).go();
    await db
        .into(db.recents)
        .insert(
          RecentsCompanion.insert(
            kind: kind,
            value: trimmed,
            label: label,
            at: DateTime.now(),
          ),
        );

    final stale =
        await (db.select(db.recents)
              ..where((t) => t.kind.equalsValue(kind))
              ..orderBy([(t) => OrderingTerm.desc(t.at)])
              ..limit(1000, offset: _keep))
            .get();
    if (stale.isNotEmpty) {
      await (db.delete(
        db.recents,
      )..where((t) => t.id.isIn(stale.map((r) => r.id)))).go();
    }
  });
}

Future<List<RecentItem>> recentItems(AppDatabase db, RecentKind kind) =>
    (db.select(db.recents)
          ..where((t) => t.kind.equalsValue(kind))
          ..orderBy([(t) => OrderingTerm.desc(t.at)]))
        .get();

Future<void> clearRecent(AppDatabase db, [RecentKind? kind]) async {
  final query = db.delete(db.recents);
  if (kind != null) query.where((t) => t.kind.equalsValue(kind));
  await query.go();
}
