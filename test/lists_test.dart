import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';

import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  group('system lists', () {
    test('seeds the three built-ins once, in order', () async {
      final first = await allLists(db);
      final second = await allLists(db);
      expect(first.map((l) => l.id), ['known', 'favourites', 'learning']);
      expect(second, hasLength(3));
    });

    test('cannot be deleted', () async {
      await allLists(db);
      await deleteList(db, 'known');
      expect(await allLists(db), hasLength(3));
    });

    test('user lists come after, alphabetically', () async {
      await allLists(db);
      await createList(db, 'Zoo');
      await createList(db, 'Anchor');
      expect((await allLists(db)).map((l) => l.name), [
        'Kenne ich schon',
        'Favoriten',
        'Lernen',
        'Anchor',
        'Zoo',
      ]);
    });
  });

  group('membership', () {
    test('reads back in insertion order and removes', () async {
      final list = await createList(db, 'Kitchen');
      await addToList(db, list.id, [7, 3, 9]);
      expect(await listEntryIds(db, list.id), [7, 3, 9]);

      await removeFromList(db, list.id, [3]);
      expect(await listEntryIds(db, list.id), [7, 9]);
    });

    test('keeps the slot when an entry is added again', () async {
      final list = await createList(db, 'Kitchen');
      await addToList(db, list.id, [7, 3, 9]);
      await addToList(db, list.id, [3]);
      expect(await listEntryIds(db, list.id), [7, 3, 9]);
    });

    test('does not duplicate', () async {
      final list = await createList(db, 'Kitchen');
      await addToList(db, list.id, [7]);
      await addToList(db, list.id, [7]);
      expect(await listEntryIds(db, list.id), [7]);
    });

    test('toggles both ways', () async {
      final list = await createList(db, 'Kitchen');
      expect(await toggleInList(db, list.id, 42), isTrue);
      expect(await toggleInList(db, list.id, 42), isFalse);
      expect(await listEntryIds(db, list.id), isEmpty);
    });

    test('reports every list an entry belongs to', () async {
      final a = await createList(db, 'A');
      final b = await createList(db, 'B');
      await addToList(db, a.id, [1]);
      await addToList(db, b.id, [1]);
      expect(await listsContaining(db, 1), {a.id, b.id});
    });

    test('counts per list', () async {
      final a = await createList(db, 'A');
      await addToList(db, a.id, [1, 2, 3]);
      expect((await listCounts(db))[a.id], 3);
    });
  });

  group('maintenance', () {
    test('renames, ignoring blank input', () async {
      final list = await createList(db, 'Old');
      await renameList(db, list.id, '  New  ');
      expect(
        (await allLists(db)).firstWhere((l) => l.id == list.id).name,
        'New',
      );
      await renameList(db, list.id, '   ');
      expect(
        (await allLists(db)).firstWhere((l) => l.id == list.id).name,
        'New',
      );
    });

    test('deletes a user list together with its items', () async {
      final list = await createList(db, 'Gone');
      await addToList(db, list.id, [1, 2]);
      await deleteList(db, list.id);
      expect((await allLists(db)).where((l) => l.id == list.id), isEmpty);
      expect(await listEntryIds(db, list.id), isEmpty);
    });

    test('duplicates contents into a new list', () async {
      final source = await createList(db, 'Original');
      await addToList(db, source.id, [4, 5]);
      final copy = await duplicateList(db, source.id, 'Copy');
      expect(await listEntryIds(db, copy!.id), [4, 5]);
    });
  });
}
