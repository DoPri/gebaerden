// Narrow import, drift also exports isNull and isNotNull.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/srs/scheduler.dart';

import 'support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = testDb());
  tearDown(() => db.close());

  Future<void> seed(int count, {bool withVideo = true}) async {
    await cacheEntries(db, [
      for (var i = 1; i <= count; i++)
        sampleEntry(
          id: i,
          text: 'Word $i',
          currentVideo: withVideo ? sampleVideo : null,
        ),
    ]);
  }

  group('deck', () {
    test('takes only entries with video', () async {
      await seed(3);
      await cacheEntries(db, [sampleEntry(id: 99, text: 'No video')]);

      final deck = await buildDeck(db);
      expect(deck.cards.map((c) => c.entryId), isNot(contains(99)));
      expect(deck.newCount, 3);
    });

    test('skips what is marked as known', () async {
      await seed(3);
      await addToList(db, knownList, [2]);

      final deck = await buildDeck(db);
      expect(deck.cards.map((c) => c.entryId), isNot(contains(2)));
    });

    test('honours the daily limit for new cards', () async {
      await seed(50);
      final deck = await buildDeck(db, const DeckOptions(newLimit: 5));
      expect(deck.cards, hasLength(5));
      expect(deck.newCount, 50, reason: 'counts all, returns only the limit');
    });

    test('newLimit 0 yields nothing new but keeps counting', () async {
      await seed(10);
      final deck = await buildDeck(db, const DeckOptions(newLimit: 0));
      expect(deck.cards, isEmpty);
      expect(deck.newCount, 10);
    });

    test('both directions give two cards per word', () async {
      await seed(4);
      final deck = await buildDeck(
        db,
        const DeckOptions(
          directions: [Direction.recognition, Direction.production],
        ),
      );
      expect(deck.newCount, 8);
    });

    test('narrows to a list', () async {
      await seed(10);
      final deck = await buildDeck(db, const DeckOptions(entryIds: [3, 7]));
      expect(deck.cards.map((c) => c.entryId).toSet(), {3, 7});
    });

    test('suspended cards stay out', () async {
      await seed(2);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      await db
          .into(db.cards)
          .insertOnConflictUpdate(card.copyWith(suspended: true));

      final deck = await buildDeck(db);
      expect(deck.cards.map((c) => c.entryId), isNot(contains(1)));
    });

    test('due cards come before new ones, oldest debt first', () async {
      await seed(3);
      final past = DateTime.now().subtract(const Duration(days: 1));
      // Entry 2 is the older debt.
      for (final (entryId, hoursOverdue) in [(1, 2), (2, 5)]) {
        final card = await getOrCreateCard(db, entryId, Direction.recognition);
        await db
            .into(db.cards)
            .insertOnConflictUpdate(
              card.copyWith(
                stability: const Value(10),
                difficulty: const Value(5),
                state: f.State.review.value,
                due: past.subtract(Duration(hours: hoursOverdue)),
              ),
            );
      }

      final deck = await buildDeck(db);
      expect(deck.dueCount, 2);
      expect(deck.cards.take(2).map((c) => c.entryId), [2, 1]);
    });
  });

  group('grading', () {
    test('pushes the card back and logs a review', () async {
      await seed(1);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      final graded = await gradeCard(db, card, f.Rating.good);

      expect(graded.due.isAfter(card.due), isTrue);
      expect(graded.reps, 1);
      expect(isNew(graded), isFalse);
      expect(await db.select(db.reviews).get(), hasLength(1));
    });

    test('counts a lapse only when a review card is forgotten', () async {
      await seed(1);
      var card = await getOrCreateCard(db, 1, Direction.recognition);

      // Fresh and forgotten is not a lapse.
      card = await gradeCard(db, card, f.Rating.again);
      expect(card.lapses, 0);

      card = card.copyWith(state: f.State.review.value);
      card = await gradeCard(db, card, f.Rating.again);
      expect(card.lapses, 1);
    });

    test('suspends a card at eight lapses', () async {
      await seed(1);
      var card = (await getOrCreateCard(db, 1, Direction.recognition)).copyWith(
        state: f.State.review.value,
        stability: const Value(10),
        difficulty: const Value(5),
        lapses: leechLapses - 1,
      );

      card = await gradeCard(db, card, f.Rating.again);
      expect(card.lapses, leechLapses);
      expect(card.suspended, isTrue);
    });

    test('a row without stability does not kill the trainer', () async {
      await seed(1);
      // Only a corrupted database can produce this, and dart-fsrs
      // dereferences stability unchecked.
      final broken = (await getOrCreateCard(
        db,
        1,
        Direction.recognition,
      )).copyWith(state: f.State.review.value);

      final graded = await gradeCard(db, broken, f.Rating.good);
      expect(graded.stability, isNotNull);
    });
  });

  group('undo', () {
    test('restores the card and the counter', () async {
      await seed(1);
      final before = await getOrCreateCard(db, 1, Direction.recognition);
      await db.into(db.cards).insertOnConflictUpdate(before);
      await gradeCard(db, before, f.Rating.easy);

      final restored = await undoLast(db);
      expect(restored, isNotNull);
      expect(restored!.reps, before.reps);
      expect(restored.due, before.due);
      expect(restored.stability, before.stability);
      expect(await db.select(db.reviews).get(), isEmpty);
    });

    test('takes a lapse back too', () async {
      await seed(1);
      final before = (await getOrCreateCard(db, 1, Direction.recognition))
          .copyWith(
            state: f.State.review.value,
            stability: const Value(10),
            difficulty: const Value(5),
            lapses: 3,
          );
      await db.into(db.cards).insertOnConflictUpdate(before);

      await gradeCard(db, before, f.Rating.again);
      final restored = await undoLast(db);
      expect(restored!.lapses, 3);
      expect(restored.suspended, isFalse);
    });

    test('nothing to undo without a review', () async {
      expect(await undoLast(db), isNull);
    });
  });

  group('today', () {
    test('counts today only and separates new from review', () async {
      await seed(2);
      final fresh = await getOrCreateCard(db, 1, Direction.recognition);
      await gradeCard(db, fresh, f.Rating.good);

      final seen = (await getOrCreateCard(db, 2, Direction.recognition))
          .copyWith(
            stability: const Value(10),
            difficulty: const Value(5),
            state: f.State.review.value,
          );
      await gradeCard(db, seen, f.Rating.good);

      final today = await reviewedToday(db);
      expect(today.total, 2);
      expect(today.fresh, 1);
    });

    test('yesterday does not count', () async {
      await seed(1);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      await gradeCard(
        db,
        card,
        f.Rating.good,
        now: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect((await reviewedToday(db)).total, 0);
    });
  });

  test('preview names an interval for every grade', () async {
    await seed(1);
    final card = await getOrCreateCard(db, 1, Direction.recognition);
    final preview = previewIntervals(card);

    expect(preview.keys, containsAll(grades));
    expect(preview.values.every((v) => v.isNotEmpty), isTrue);
  });

  test('preview leaves the card alone', () async {
    await seed(1);
    final card = await getOrCreateCard(db, 1, Direction.recognition);
    previewIntervals(card);
    expect(await db.select(db.reviews).get(), isEmpty);
  });
}
