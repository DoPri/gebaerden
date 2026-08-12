import 'api/queries.dart';
import 'db/database.dart';
import 'db/lists.dart';
import 'db/repo.dart';

class Topic {
  const Topic(this.name, this.words);

  final String name;
  final List<String> words;
}

/// Every word checked against the live API. Missing ones were dropped.
const topics = [
  Topic('Begrüßung', [
    'Hallo',
    'Tschüss',
    'Danke',
    'Bitte',
    'Ja',
    'Nein',
    'Entschuldigung',
    'Guten Morgen',
    'Gute Nacht',
    'Willkommen',
  ]),
  Topic('Familie', [
    'Mutter',
    'Vater',
    'Kind',
    'Bruder',
    'Schwester',
    'Oma',
    'Opa',
    'Familie',
    'Freund',
    'Frau',
    'Mann',
    'Baby',
    'Sohn',
    'Tochter',
  ]),
  Topic('Farben', [
    'Rot',
    'Blau',
    'Grün',
    'Gelb',
    'Schwarz',
    'Weiß',
    'Braun',
    'Orange',
    'Grau',
    'Rosa',
    'Lila',
    'Farbe',
  ]),
  Topic('Essen und Trinken', [
    'Brot',
    'Wasser',
    'Milch',
    'Apfel',
    'Kaffee',
    'Tee',
    'Essen',
    'Trinken',
    'Käse',
    'Fleisch',
    'Obst',
    'Gemüse',
    'Suppe',
    'Kuchen',
  ]),
  Topic('Zeit', [
    'Heute',
    'Morgen',
    'Gestern',
    'Woche',
    'Monat',
    'Jahr',
    'Stunde',
    'Minute',
    'Jetzt',
    'Später',
    'Uhr',
    'Zeit',
  ]),
  Topic('Wochentage', [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ]),
  Topic('Gefühle', [
    'Glücklich',
    'Traurig',
    'Müde',
    'Angst',
    'Liebe',
    'Lachen',
    'Weinen',
    'Krank',
    'Gesund',
  ]),
  Topic('Unterwegs', [
    'Auto',
    'Bus',
    'Zug',
    'Fahrrad',
    'Flugzeug',
    'Straße',
    'Bahnhof',
    'Fahren',
    'Laufen',
    'Weg',
  ]),
];

/// Resolves the words, caches them and drops them into a fresh list.
Future<StoredList?> importTopic(AppDatabase db, Topic topic) async {
  final ids = (await resolveExact(topic.words)).values.toList();
  if (ids.isEmpty) return null;

  final rows = await cacheEntries(db, await fetchEntries(ids));
  final usable = rows.where((r) => r.hasVideo).map((r) => r.id).toList();
  if (usable.isEmpty) return null;

  final list = await createList(db, topic.name);
  await addToList(db, list.id, usable);
  return list;
}
