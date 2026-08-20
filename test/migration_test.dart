import 'dart:io';

// Avoids symbol collision with flutter_test isNull/isNotNull.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';

/// Tests migrations across multiple schema versions from v1.
void main() {
  late Directory tmp;
  late File file;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tmp = Directory.systemTemp.createTempSync('migration_test');
    file = File('${tmp.path}/gebaerden.sqlite');

    // Rolls back generated schema to v1 to keep base schema synchronized.
    final old = AppDatabase(NativeDatabase(file));
    await old.customStatement('ALTER TABLE lists DROP COLUMN new_per_day');
    await old.customStatement('ALTER TABLE lists DROP COLUMN review_per_day');
    await old.customStatement('DROP TABLE reminders');
    await old.batch(
      (b) => b.insertAll(old.settings, const [
        StoredSetting(key: 'reminders', value: '1234567 19:00'),
        StoredSetting(key: 'reminderAt', value: '19:00'),
        StoredSetting(key: 'newPerDay', value: 7),
      ]),
    );
    await old.customStatement('PRAGMA user_version = 1');
    await old.close();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('an old database keeps its rows and gains the new columns', () async {
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    await db
        .into(db.lists)
        .insert(
          StoredList(
            id: 'kueche',
            name: 'Küche',
            kind: ListKind.custom,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

    final list = (await db.select(db.lists).get()).single;
    expect(list.newPerDay, isNull);
    expect(list.reviewPerDay, isNull);
    expect((await db.select(db.settings).get()).single.key, 'newPerDay');
  });

  test('the global reminder goes, its table takes over', () async {
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // Deprecated global reminders without associated lists are purged.
    final keys = (await db.select(db.settings).get()).map((s) => s.key);
    expect(keys, isNot(contains('reminders')));
    expect(keys, isNot(contains('reminderAt')));
    expect(await db.select(db.reminders).get(), isEmpty);
  });
}
