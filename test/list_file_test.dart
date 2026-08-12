import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/transfer/list_file.dart';

import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  Future<StoredList> seed() async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Tschüss', currentVideo: sampleVideo),
    ]);
    final list = await createList(db, 'Begrüßung');
    await addToList(db, list.id, [2, 1]);
    return list;
  }

  test('round trip keeps name, order and words', () async {
    final list = await seed();
    final shared = parseListFile(await encodeList(db, list));

    expect(shared.name, 'Begrüßung');
    expect(shared.entries.map((e) => e.id), [2, 1]);
    expect(shared.entries.map((e) => e.word), ['Tschüss', 'Hallo']);
  });

  test('the file name keeps umlauts', () {
    expect(listFileName('Begrüßung (Kopie)'), 'Begrüßung (Kopie).dgsliste');
  });

  test('the file name drops what a path cannot hold', () {
    expect(listFileName('a/b:c*d'), 'abcd.dgsliste');
    expect(listFileName('///'), 'Liste.dgsliste');
  });

  test('rejects a foreign file', () {
    expect(
      () => parseListFile('{"schema":"etwas-anderes"}'),
      throwsA(isA<ListFileError>()),
    );
  });

  test('rejects broken json', () {
    expect(() => parseListFile('kein json'), throwsA(isA<ListFileError>()));
  });

  test('rejects a damaged entry', () {
    expect(
      () => parseListFile(
        '{"schema":"$listSchema","name":"A","entries":[{"id":"x"}]}',
      ),
      throwsA(isA<ListFileError>()),
    );
  });

  test('a nameless list still gets a name', () {
    final shared = parseListFile(
      '{"schema":"$listSchema","name":"  ","entries":[]}',
    );
    expect(shared.name, 'Geteilte Liste');
  });

  test('import creates the list in the order of the file', () async {
    final list = await seed();
    final text = await encodeList(db, list);
    await deleteList(db, list.id);

    final made = await importSharedList(db, parseListFile(text));
    expect(made.name, 'Begrüßung');
    expect(await listEntryIds(db, made.id), [2, 1]);
  });
}
