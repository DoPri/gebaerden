import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as f;

import '../db/database.dart';
import '../db/lists.dart';
import '../util/time.dart';

/// Fuzz on, or a big batch all falls due the same day.
final _scheduler = f.Scheduler();

final _random = Random();

const grades = [f.Rating.again, f.Rating.hard, f.Rating.good, f.Rating.easy];

/// Beyond this a card costs more time than it returns.
const leechLapses = 8;

String cardId(int entryId, Direction direction) => '$entryId:${direction.name}';

/// dart-fsrs has no New state.
bool isNew(StoredCard card) => card.stability == null;

StoredCard newCard(int entryId, Direction direction, DateTime now) =>
    StoredCard(
      id: cardId(entryId, direction),
      entryId: entryId,
      direction: direction,
      state: f.State.learning.value,
      step: 0,
      due: now,
      reps: 0,
      lapses: 0,
      suspended: false,
    );

/// dart-fsrs dereferences stability once a card is past learning.
f.Card _toFsrs(StoredCard card) => f.Card(
  cardId: card.entryId,
  state: isNew(card) ? f.State.learning : f.State.fromValue(card.state),
  step: isNew(card) ? 0 : card.step,
  stability: card.stability,
  difficulty: card.difficulty,
  due: card.due.toUtc(),
  lastReview: card.lastReview?.toUtc(),
);

/// The default rounds timestamps to milliseconds.
final _exact = ValueSerializer.defaults(serializeDateTimeValuesAsString: true);

StoredCard _merge(
  StoredCard card,
  f.Card next, {
  required int reps,
  required int lapses,
}) => card.copyWith(
  state: next.state.value,
  step: Value(next.step),
  stability: Value(next.stability),
  difficulty: Value(next.difficulty),
  due: next.due.toLocal(),
  lastReview: Value(next.lastReview?.toLocal()),
  reps: reps,
  lapses: lapses,
  suspended: lapses >= leechLapses,
);

Future<StoredCard> getOrCreateCard(
  AppDatabase db,
  int entryId,
  Direction direction,
) async {
  final id = cardId(entryId, direction);
  final stored = await (db.select(
    db.cards,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  return stored ?? newCard(entryId, direction, DateTime.now());
}

class DeckOptions {
  const DeckOptions({
    this.entryIds,
    this.directions = const [Direction.recognition],
    this.newLimit = 20,
    this.reviewLimit = 200,
    this.now,
  });

  /// Null means the whole local cache.
  final List<int>? entryIds;
  final List<Direction> directions;
  final int newLimit;
  final int reviewLimit;
  final DateTime? now;
}

class Deck {
  const Deck({
    required this.cards,
    required this.dueCount,
    required this.newCount,
  });

  final List<StoredCard> cards;
  final int dueCount;
  final int newCount;
}

/// Without video and already known are both out.
Future<List<int>> _candidates(AppDatabase db, DeckOptions opts) async {
  final query = db.selectOnly(db.entries)..addColumns([db.entries.id]);
  query.where(
    opts.entryIds == null
        ? db.entries.hasVideo.equals(true)
        : db.entries.hasVideo.equals(true) & db.entries.id.isIn(opts.entryIds!),
  );
  final withVideo = (await query.get()).map((r) => r.read(db.entries.id)!);

  final known = (await listEntryIds(db, knownList)).toSet();
  return withVideo.where((id) => !known.contains(id)).toList();
}

Future<Deck> buildDeck(
  AppDatabase db, [
  DeckOptions opts = const DeckOptions(),
]) async {
  final now = opts.now ?? DateTime.now();
  final entryIds = await _candidates(db, opts);

  // Cheaper than one lookup per candidate, most hold no row at all.
  final stored = {
    for (final card in await db.select(db.cards).get()) card.id: card,
  };

  final due = <StoredCard>[];
  final fresh = List<StoredCard?>.filled(opts.newLimit, null);
  var newCount = 0;

  for (final entryId in entryIds) {
    for (final direction in opts.directions) {
      final card = stored[cardId(entryId, direction)];
      if (card?.suspended == true) continue;

      if (card != null && !isNew(card)) {
        if (!card.due.isAfter(now)) due.add(card);
        continue;
      }

      // Reservoir sampling, so no thousands of cards get built and dropped.
      final seen = newCount++;
      final slot = seen < opts.newLimit ? seen : _random.nextInt(newCount);
      if (slot >= opts.newLimit) continue;

      fresh[slot] = card ?? newCard(entryId, direction, now);
    }
  }

  due.sort((a, b) => a.due.compareTo(b.due));

  return Deck(
    cards: [...due.take(opts.reviewLimit), ...fresh.whereType<StoredCard>()],
    dueCount: due.length,
    newCount: newCount,
  );
}

Future<StoredCard> gradeCard(
  AppDatabase db,
  StoredCard card,
  f.Rating rating, {
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).toUtc();
  final result = _scheduler.reviewCard(
    _toFsrs(card),
    rating,
    reviewDateTime: at,
  );

  final lapsed =
      rating == f.Rating.again &&
      !isNew(card) &&
      card.state == f.State.review.value;
  final updated = _merge(
    card,
    result.card,
    reps: card.reps + 1,
    lapses: card.lapses + (lapsed ? 1 : 0),
  );

  await db.transaction(() async {
    await db.into(db.cards).insertOnConflictUpdate(updated);
    await db
        .into(db.reviews)
        .insert(
          ReviewsCompanion.insert(
            cardId: card.id,
            entryId: card.entryId,
            rating: rating.value,
            reviewedAt: at.toLocal(),
            before: jsonEncode(card.toJson(serializer: _exact)),
          ),
        );
  });
  return updated;
}

/// dart-fsrs has no rollback, so the review row carries the old card.
Future<StoredCard?> undoLast(AppDatabase db) async {
  final last =
      await (db.select(db.reviews)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();
  if (last == null) return null;

  final restored = StoredCard.fromJson(
    jsonDecode(last.before) as Map<String, dynamic>,
    serializer: _exact,
  );

  await db.transaction(() async {
    await db.into(db.cards).insertOnConflictUpdate(restored);
    await (db.delete(db.reviews)..where((t) => t.id.equals(last.id))).go();
  });
  return restored;
}

class TodayCount {
  const TodayCount({required this.total, required this.fresh});

  final int total;
  final int fresh;
}

/// The review log is the counter, no extra bookkeeping.
/// [entryIds] narrows the count to one list, so its budget is its own.
Future<TodayCount> reviewedToday(
  AppDatabase db, {
  List<int>? entryIds,
  DateTime? now,
}) async {
  final today = now ?? DateTime.now();
  final start = DateTime(today.year, today.month, today.day);

  final logs =
      await (db.select(db.reviews)..where(
            (t) => entryIds == null
                ? t.reviewedAt.isBiggerOrEqualValue(start)
                : t.reviewedAt.isBiggerOrEqualValue(start) &
                      t.entryId.isIn(entryIds),
          ))
          .get();

  var fresh = 0;
  for (final log in logs) {
    final before = jsonDecode(log.before) as Map<String, dynamic>;
    if (before['stability'] == null) fresh++;
  }
  return TodayCount(total: logs.length, fresh: fresh);
}

/// Labels under the answer buttons.
Map<f.Rating, String> previewIntervals(StoredCard card, [DateTime? now]) {
  final at = (now ?? DateTime.now()).toUtc();
  final base = _toFsrs(card);
  return {
    for (final grade in grades)
      grade: humanInterval(
        _scheduler
            .reviewCard(base, grade, reviewDateTime: at)
            .card
            .due
            .toLocal(),
        at.toLocal(),
      ),
  };
}
