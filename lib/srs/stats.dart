import 'package:fsrs/fsrs.dart' as f;

import '../db/database.dart';

class DayCount {
  const DayCount(this.day, this.count);

  final DateTime day;
  final int count;
}

class Stats {
  const Stats({
    required this.streak,
    required this.history,
    required this.forecast,
    required this.cards,
    required this.retained,
  });

  final int streak;
  final List<DayCount> history;
  final List<DayCount> forecast;
  final int cards;

  /// Cards past the initial learning phase.
  final int retained;
}

DateTime _day(DateTime at) => DateTime(at.year, at.month, at.day);

/// Shifts calendar days directly to prevent DST hour offsets from skewing midnight keys.
DateTime _shift(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

int streakFrom(Set<DateTime> days, DateTime today) {
  // Preserves streak if today has no reviews yet.
  var cursor = days.contains(_day(today))
      ? _day(today)
      : _shift(_day(today), -1);

  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = _shift(cursor, -1);
  }
  return streak;
}

Future<Stats> collectStats(
  AppDatabase db, {
  DateTime? now,
  int historyDays = 14,
}) async {
  final today = _day(now ?? DateTime.now());
  final reviews = await db.select(db.reviews).get();
  final cards = await db.select(db.cards).get();

  final reviewed = <DateTime, int>{};
  for (final review in reviews) {
    final key = _day(review.reviewedAt);
    reviewed[key] = (reviewed[key] ?? 0) + 1;
  }

  final due = <DateTime, int>{};
  for (final card in cards) {
    if (card.stability == null || card.suspended) continue;
    final key = _day(card.due);
    due[key] = (due[key] ?? 0) + 1;
  }

  final history = [
    for (var i = 0; i < historyDays; i++)
      () {
        final day = _shift(today, -(historyDays - 1 - i));
        return DayCount(day, reviewed[day] ?? 0);
      }(),
  ];

  final overdue = due.entries
      .where((e) => e.key.isBefore(today))
      .fold(0, (sum, e) => sum + e.value);

  final forecast = [
    for (var i = 0; i < 7; i++)
      () {
        final day = _shift(today, i);
        // Overdue cards are folded into today's forecast.
        return DayCount(day, (due[day] ?? 0) + (i == 0 ? overdue : 0));
      }(),
  ];

  return Stats(
    streak: streakFrom(reviewed.keys.toSet(), today),
    history: history,
    forecast: forecast,
    cards: cards.length,
    retained: cards.where((c) => c.state == f.State.review.value).length,
  );
}
