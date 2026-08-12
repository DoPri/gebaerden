import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/media/variants.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/transfer/backup.dart';
import 'package:http/http.dart' as http;

import 'harness.dart';
import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() async {
    useClient(http.Client());
    await db.close();
  });

  Future<void> seed(AppDatabase target) async {
    await cacheEntries(target, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Tschüss', currentVideo: sampleVideo),
    ]);
    final list = await createList(target, 'Begrüßung');
    await addToList(target, list.id, [1, 2]);

    final card = await getOrCreateCard(target, 1, Direction.recognition);
    await gradeCard(target, card, f.Rating.good);
    await setPreferred(target, 1, sampleVideo);
    await target
        .into(target.settings)
        .insertOnConflictUpdate(
          const StoredSetting(key: 'newPerDay', value: 7),
        );
  }

  test('a round trip carries progress, lists and settings', () async {
    await seed(db);
    final text = await exportBackup(db);

    final fresh = testDb();
    addTearDown(fresh.close);
    final summary = await importBackup(fresh, text, ImportMode.replace);

    expect(summary.cards, 1);
    expect(summary.reviews, 1);
    expect(summary.lists, greaterThanOrEqualTo(1));

    final cards = await fresh.select(fresh.cards).get();
    expect(cards.single.entryId, 1);
    expect(cards.single.reps, 1);

    final lists = await allLists(fresh);
    final copied = lists.firstWhere((l) => l.name == 'Begrüßung');
    expect(await listEntryIds(fresh, copied.id), [1, 2]);

    final settings = await fresh.select(fresh.settings).get();
    expect(settings.firstWhere((s) => s.key == 'newPerDay').value, 7);
    expect(await fresh.select(fresh.variants).get(), hasLength(1));
  });

  test('the due date survives to the microsecond', () async {
    await seed(db);
    final before = (await db.select(db.cards).get()).single;

    final fresh = testDb();
    addTearDown(fresh.close);
    await importBackup(fresh, await exportBackup(db), ImportMode.replace);

    expect((await fresh.select(fresh.cards).get()).single.due, before.due);
  });

  test('merging keeps the card with more reps', () async {
    await seed(db);
    final text = await exportBackup(db);

    // The other device answered the same word twice.
    final other = testDb();
    addTearDown(other.close);
    await cacheEntries(other, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    var card = await getOrCreateCard(other, 1, Direction.recognition);
    card = await gradeCard(other, card, f.Rating.good);
    await gradeCard(other, card, f.Rating.good);

    await importBackup(other, text, ImportMode.merge);
    expect((await other.select(other.cards).get()).single.reps, 2);
  });

  test('merging keeps the incoming card when it is further along', () async {
    await seed(db);
    var card = (await db.select(db.cards).get()).single;
    card = await gradeCard(db, card, f.Rating.good);
    final text = await exportBackup(db);

    final other = testDb();
    addTearDown(other.close);
    await cacheEntries(other, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    final behind = await getOrCreateCard(other, 1, Direction.recognition);
    await gradeCard(other, behind, f.Rating.good);

    await importBackup(other, text, ImportMode.merge);
    expect((await other.select(other.cards).get()).single.reps, 2);
  });

  test('merging adds no duplicate reviews', () async {
    await seed(db);
    final text = await exportBackup(db);

    await importBackup(db, text, ImportMode.merge);
    expect(await db.select(db.reviews).get(), hasLength(1));
  });

  test('replacing throws the local progress away', () async {
    await seed(db);
    final text = await exportBackup(db);

    final other = testDb();
    addTearDown(other.close);
    await cacheEntries(other, [
      sampleEntry(id: 9, text: 'Auto', currentVideo: sampleVideo),
    ]);
    final gone = await getOrCreateCard(other, 9, Direction.recognition);
    await gradeCard(other, gone, f.Rating.good);

    await importBackup(other, text, ImportMode.replace);
    final cards = await other.select(other.cards).get();
    expect(cards.map((c) => c.entryId), [1]);
  });

  test('taking only the lists leaves the cards alone', () async {
    await seed(db);
    final text = await exportBackup(db);

    final other = testDb();
    addTearDown(other.close);
    await importBackup(
      other,
      text,
      ImportMode.merge,
      sections: const {BackupSection.lists},
    );

    expect(await other.select(other.cards).get(), isEmpty);
    expect((await allLists(other)).map((l) => l.name), contains('Begrüßung'));
  });

  test('a section left out of the export is not in the file', () async {
    await seed(db);
    final text = await exportBackup(db, sections: const {BackupSection.lists});

    expect(sectionsIn(text), const {BackupSection.lists});
  });

  test('a foreign file is refused with a reason', () async {
    await expectLater(
      () => importBackup(db, '{"schema":"etwas-anderes"}', ImportMode.merge),
      throwsA(isA<BackupError>()),
    );
    await expectLater(
      () => importBackup(db, 'kein json', ImportMode.merge),
      throwsA(isA<BackupError>()),
    );
    await expectLater(
      () => importBackup(db, '[]', ImportMode.merge),
      throwsA(isA<BackupError>()),
    );
  });

  test('a damaged section is refused', () async {
    final broken = jsonEncode({
      'schema': backupSchema,
      'cards': [
        {'id': 'x'},
      ],
    });
    await expectLater(
      () => importBackup(db, broken, ImportMode.merge),
      throwsA(isA<BackupError>()),
    );
  });

  test('missing sections are simply empty', () async {
    final bare = jsonEncode({'schema': backupSchema});
    final summary = await importBackup(db, bare, ImportMode.merge);
    expect(summary.cards, 0);
  });

  test('the file name carries the day', () {
    expect(
      backupFileName(DateTime(2026, 8, 7)),
      'dgs-lernen-2026-08-07.dgsbackup',
    );
  });

  test('restoring pulls the words the progress points at', () async {
    await seed(db);
    final text = await exportBackup(db);

    final fresh = testDb();
    addTearDown(fresh.close);
    await importBackup(fresh, text, ImportMode.replace);

    expect(await missingEntryIds(fresh), unorderedEquals([1, 2]));

    stubPer(
      (_) => {
        'e0': {'id': 1, 'text': 'Hallo', 'currentVideo': sampleVideo.toJson()},
        'e1': {'id': 2, 'text': 'Tschüss'},
      },
    );
    expect(await restoreEntries(fresh), 2);
    expect(await missingEntryIds(fresh), isEmpty);
  });

  test('restoring does nothing when everything is there', () async {
    await seed(db);
    expect(await restoreEntries(db), 0);
  });
}
