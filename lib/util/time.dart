/// Parses upstream date format ("YYYY-MM-DD HH:MM:SS").
DateTime? parseApiDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value.replaceFirst(' ', 'T'));
}

const _units = [
  ('Jahr', 'Jahren', Duration(days: 365)),
  ('Monat', 'Monaten', Duration(days: 30)),
  ('Woche', 'Wochen', Duration(days: 7)),
  ('Tag', 'Tagen', Duration(days: 1)),
  ('Stunde', 'Stunden', Duration(hours: 1)),
  ('Minute', 'Minuten', Duration(minutes: 1)),
];

/// Provides explicit singular and plural forms for German declension.
String? relativeTime(String? value, [DateTime? now]) {
  final date = parseApiDate(value);
  if (date == null) return null;

  final diff = date.difference(now ?? DateTime.now());
  final past = diff.isNegative;
  final abs = diff.abs();

  for (final (one, many, unit) in _units) {
    // Truncates rather than rounds to prevent premature unit promotion.
    final amount = abs.inSeconds ~/ unit.inSeconds;
    if (amount == 0) continue;
    final noun = amount == 1 ? one : many;
    return past ? 'vor $amount $noun' : 'in $amount $noun';
  }
  return 'gerade eben';
}

String humanInterval(DateTime due, DateTime now) {
  final minutes = due.difference(now).inMinutes;
  if (minutes < 60) return '${minutes < 1 ? 1 : minutes} min';

  final hours = (minutes / 60).round();
  if (hours < 24) return '$hours h';

  final days = (hours / 24).round();
  if (days < 30) return '$days d';

  final months = days / 30.4;
  // Threshold avoids displaying 12 months instead of 1 year.
  if (months < 11.5) {
    return '${months.toStringAsFixed(months < 3 ? 1 : 0)} mo';
  }
  return '${(days / 365).toStringAsFixed(1)} a';
}
