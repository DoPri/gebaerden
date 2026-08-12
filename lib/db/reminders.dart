import 'package:drift/drift.dart';

import '../platform/notify.dart';
import '../srs/scheduler.dart';
import 'database.dart';
import 'lists.dart';

/// A reminder plus the list it belongs to, which is what scheduling needs to
/// count the right cards and to route a tap.
class ScopedReminder {
  const ScopedReminder({
    required this.id,
    required this.listId,
    required this.reminder,
  });

  final int id;
  final String listId;
  final Reminder reminder;
}

Reminder _from(StoredReminder row) => Reminder(
  days: {
    for (final c in row.days.split(''))
      if (int.tryParse(c) case final d? when d >= 1 && d <= 7) d,
  },
  hour: row.hour,
  minute: row.minute,
);

String _days(Set<int> days) => (days.toList()..sort()).join();

/// Every reminder on the device, in a stable order so the alarm ids do not
/// shuffle between two writes.
Future<List<ScopedReminder>> allReminders(AppDatabase db) async {
  final rows =
      await (db.select(db.reminders)..orderBy([
            (t) => OrderingTerm(expression: t.listId),
            (t) => OrderingTerm(expression: t.id),
          ]))
          .get();
  return [
    for (final row in rows)
      ScopedReminder(id: row.id, listId: row.listId, reminder: _from(row)),
  ];
}

Future<List<ScopedReminder>> remindersFor(AppDatabase db, String listId) async {
  final rows =
      await (db.select(db.reminders)
            ..where((t) => t.listId.equals(listId))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
  return [
    for (final row in rows)
      ScopedReminder(id: row.id, listId: row.listId, reminder: _from(row)),
  ];
}

Future<void> addReminder(
  AppDatabase db,
  String listId,
  Reminder reminder,
) async {
  await db
      .into(db.reminders)
      .insert(
        RemindersCompanion.insert(
          listId: listId,
          days: _days(reminder.days),
          hour: reminder.hour,
          minute: reminder.minute,
        ),
      );
}

Future<void> setReminder(AppDatabase db, int id, Reminder reminder) async {
  await (db.update(db.reminders)..where((t) => t.id.equals(id))).write(
    RemindersCompanion(
      days: Value(_days(reminder.days)),
      hour: Value(reminder.hour),
      minute: Value(reminder.minute),
    ),
  );
}

Future<void> removeReminder(AppDatabase db, int id) async {
  await (db.delete(db.reminders)..where((t) => t.id.equals(id))).go();
}

/// Every reminder with the count of its own list, which is what the text says.
/// Counted once per list, several reminders on one list share the number.
Future<List<DueReminder>> dueReminders(
  AppDatabase db,
  List<Direction> directions,
) async {
  final counted = <String, int>{};
  final out = <DueReminder>[];

  for (final scoped in await allReminders(db)) {
    var due = counted[scoped.listId];
    if (due == null) {
      final deck = await buildDeck(
        db,
        DeckOptions(
          entryIds: await listEntryIds(db, scoped.listId),
          directions: directions,
          newLimit: 0,
          reviewLimit: 0,
        ),
      );
      due = counted[scoped.listId] = deck.dueCount;
    }
    out.add((reminder: scoped.reminder, listId: scoped.listId, due: due));
  }
  return out;
}
