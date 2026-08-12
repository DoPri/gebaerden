import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/recent.dart';

import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  test('newest first', () async {
    await remember(db, RecentKind.search, 'haus', 'haus');
    await remember(db, RecentKind.search, 'baum', 'baum');
    expect((await recentItems(db, RecentKind.search)).map((r) => r.value), [
      'baum',
      'haus',
    ]);
  });

  test('the same query moves up instead of doubling', () async {
    await remember(db, RecentKind.search, 'haus', 'haus');
    await remember(db, RecentKind.search, 'baum', 'baum');
    await remember(db, RecentKind.search, 'haus', 'haus');

    final items = await recentItems(db, RecentKind.search);
    expect(items.map((r) => r.value), ['haus', 'baum']);
  });

  test('keeps the two kinds apart', () async {
    await remember(db, RecentKind.search, 'haus', 'haus');
    await remember(db, RecentKind.entry, '42', 'Haus');

    expect(await recentItems(db, RecentKind.search), hasLength(1));
    expect(await recentItems(db, RecentKind.entry), hasLength(1));
  });

  test('stops at twenty per kind', () async {
    for (var i = 0; i < 25; i++) {
      await remember(db, RecentKind.search, 'wort$i', 'Wort $i');
    }
    final items = await recentItems(db, RecentKind.search);
    expect(items, hasLength(20));
    expect(items.first.value, 'wort24');
    expect(items.map((r) => r.value), isNot(contains('wort0')));
  });

  test('ignores blank input', () async {
    await remember(db, RecentKind.search, '   ', 'egal');
    expect(await recentItems(db, RecentKind.search), isEmpty);
  });

  test('clearing takes one kind or everything', () async {
    await remember(db, RecentKind.search, 'haus', 'haus');
    await remember(db, RecentKind.entry, '42', 'Haus');

    await clearRecent(db, RecentKind.search);
    expect(await recentItems(db, RecentKind.search), isEmpty);
    expect(await recentItems(db, RecentKind.entry), hasLength(1));

    await clearRecent(db);
    expect(await recentItems(db, RecentKind.entry), isEmpty);
  });
}
