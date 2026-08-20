import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/theme.dart';

import 'support.dart';

void main() {
  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    db = testDb();
    settings = AppSettings(db);
    await settings.load();
  });

  tearDown(() => db.close());

  test('knows defaults without a stored row', () {
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.newPerDay, 20);
    expect(settings.mode, ReviewMode.self);
    expect(settings.accent, defaultAccent);
  });

  test('keeps what was set, across a restart', () async {
    await settings.set('newPerDay', 7);
    await settings.setThemeMode(ThemeMode.dark);

    final again = AppSettings(db);
    await again.load();
    expect(again.newPerDay, 7);
    expect(again.themeMode, ThemeMode.dark);
  });

  test('the playback speed comes back after a restart', () async {
    await settings.set('speed', 0.25);

    final again = AppSettings(db);
    await again.load();
    expect(again.speed, 0.25);
  });

  test('a whole number for a decimal setting is taken as one', () async {
    // JS and imported JSON represent whole floats as ints.
    await db
        .into(db.settings)
        .insertOnConflictUpdate(const StoredSetting(key: 'speed', value: 2));

    final again = AppSettings(db);
    await again.load();
    expect(again.speed, 2.0);
  });

  test('a decimal for a whole setting is taken as one', () async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          const StoredSetting(key: 'newPerDay', value: 7.0),
        );

    final again = AppSettings(db);
    await again.load();
    expect(again.newPerDay, 7);
  });

  test('a value of the wrong kind is left alone', () async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          const StoredSetting(key: 'speed', value: 'schnell'),
        );

    final again = AppSettings(db);
    await again.load();
    expect(again.speed, 1.0);
  });

  test('announces changes', () async {
    var calls = 0;
    settings.addListener(() => calls++);
    await settings.set('mirror', true);
    expect(calls, 1);
    expect(settings.mirror, isTrue);
  });

  test('ignores a value of the wrong type', () async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          const StoredSetting(key: 'newPerDay', value: 'many'),
        );

    final again = AppSettings(db);
    await again.load();
    expect(again.newPerDay, 20);
  });

  test('ignores an unknown key', () async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(const StoredSetting(key: 'nonsense', value: 1));

    final again = AppSettings(db);
    await expectLater(again.load(), completes);
  });

  test('falls back when a stored name matches no enum', () async {
    // Handles corrupted enum strings in imported backups.
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.settings, const [
        StoredSetting(key: 'mode', value: 'unsinn'),
        StoredSetting(key: 'direction', value: 'unsinn'),
      ]),
    );

    final again = AppSettings(db);
    await again.load();
    expect(again.mode, ReviewMode.self);
    expect(again.direction, DirectionMode.recognition);
    expect(again.directions, [Direction.recognition]);
  });

  test('both means two directions', () async {
    await settings.set('direction', DirectionMode.both.name);
    expect(settings.directions, [Direction.recognition, Direction.production]);
  });
}
