import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/srs/stats.dart';

import 'support.dart';

void main() {
  late AppDatabase db;
  final today = DateTime(2026, 8, 7, 12);

  DateTime daysAgo(int n) => today.subtract(Duration(days: n));

  setUp(() => db = testDb());
  tearDown(() => db.close());

  group('streak', () {
    Set<DateTime> days(List<int> ago) => ago
        .map((n) => DateTime(2026, 8, 7).subtract(Duration(days: n)))
        .toSet();

    test('counts back from today', () {
      expect(streakFrom(days([0, 1, 2]), today), 3);
    });

    test('a blank today does not break yesterday', () {
      expect(streakFrom(days([1, 2]), today), 2);
    });

    test('a gap ends it', () {
      expect(streakFrom(days([0, 1, 3, 4]), today), 2);
    });

    test('no days at all is zero', () {
      expect(streakFrom({}, today), 0);
    });

    test('a streak counts across both clock changes', () {
      // Europe/Berlin moves the clock on the last Sunday of March and
      // October. Under UTC these are ordinary days, so the test holds there
      // too. Under the device zone it only passes when the shift lands back
      // on midnight.
      final spring = {
        DateTime(2026, 3, 28),
        DateTime(2026, 3, 29),
        DateTime(2026, 3, 30),
      };
      expect(streakFrom(spring, DateTime(2026, 3, 30, 12)), 3);

      final fall = {
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 25),
        DateTime(2026, 10, 26),
      };
      expect(streakFrom(fall, DateTime(2026, 10, 26, 12)), 3);
    });
  });

  group('collect', () {
    Future<void> review(int entryId, {required int ago}) async {
      await cacheEntries(db, [
        sampleEntry(
          id: entryId,
          text: 'Word $entryId',
          currentVideo: sampleVideo,
        ),
      ]);
      final card = await getOrCreateCard(db, entryId, Direction.recognition);
      await gradeCard(db, card, f.Rating.good, now: daysAgo(ago));
    }

    test(
      'history covers the asked window and lands on the right days',
      () async {
        await review(1, ago: 0);
        await review(2, ago: 3);

        final stats = await collectStats(db, now: today);
        expect(stats.history, hasLength(14));
        expect(stats.history.last.count, 1);
        expect(stats.history[10].count, 1);
        expect(stats.history[9].count, 0);
      },
    );

    test('forecast is seven days and folds overdue into today', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'A', currentVideo: sampleVideo),
      ]);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      await db
          .into(db.cards)
          .insertOnConflictUpdate(
            card.copyWith(
              stability: const Value(10),
              difficulty: const Value(5),
              state: f.State.review.value,
              due: daysAgo(4),
            ),
          );

      final stats = await collectStats(db, now: today);
      expect(stats.forecast, hasLength(7));
      expect(stats.forecast.first.count, 1);
    });

    test('never reviewed cards stay out of the forecast', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'A', currentVideo: sampleVideo),
      ]);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      await db.into(db.cards).insertOnConflictUpdate(card);

      final stats = await collectStats(db, now: today);
      expect(stats.forecast.fold(0, (sum, d) => sum + d.count), 0);
    });

    test('suspended cards stay out of the forecast', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'A', currentVideo: sampleVideo),
      ]);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      await db
          .into(db.cards)
          .insertOnConflictUpdate(
            card.copyWith(
              stability: const Value(10),
              difficulty: const Value(5),
              state: f.State.review.value,
              due: today,
              suspended: true,
            ),
          );

      final stats = await collectStats(db, now: today);
      expect(stats.forecast.first.count, 0);
    });

    test('counts cards and how many are past learning', () async {
      await review(1, ago: 0);
      final stats = await collectStats(db, now: today);
      expect(stats.cards, 1);
      expect(stats.retained, lessThanOrEqualTo(stats.cards));
    });

    test('an empty database returns zeroes, not an error', () async {
      final stats = await collectStats(db, now: today);
      expect(stats.cards, 0);
      expect(stats.streak, 0);
      expect(stats.history, hasLength(14));
    });

    test('history keeps the clock-change day in its slot', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Word 1', currentVideo: sampleVideo),
      ]);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      await gradeCard(db, card, f.Rating.good, now: DateTime(2026, 3, 29, 9));

      final stats = await collectStats(db, now: DateTime(2026, 3, 30, 12));
      expect(stats.history[12].count, 1);
      expect(stats.history.last.count, 0);
    });

    test('forecast lands on the day after the long autumn day', () async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'A', currentVideo: sampleVideo),
      ]);
      final card = await getOrCreateCard(db, 1, Direction.recognition);
      await db
          .into(db.cards)
          .insertOnConflictUpdate(
            card.copyWith(
              stability: const Value(10),
              difficulty: const Value(5),
              state: f.State.review.value,
              due: DateTime(2026, 10, 26),
            ),
          );

      // The clock change itself is today. Tomorrow is one calendar day away.
      final stats = await collectStats(db, now: DateTime(2026, 10, 25, 12));
      expect(stats.forecast[1].count, 1);
    });
  });
}
