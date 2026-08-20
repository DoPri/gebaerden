import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/util/text.dart';
import 'package:gebaerden/util/time.dart';

void main() {
  group('typed answers', () {
    test('case does not matter', () {
      expect(answersMatch('haus', 'Haus'), isTrue);
    });

    test('umlauts may be rewritten, both ways', () {
      expect(answersMatch('Fuss', 'Fuß'), isTrue);
      expect(answersMatch('Fuß', 'Fuss'), isTrue);
      expect(answersMatch('Baer', 'Bär'), isTrue);
      expect(answersMatch('Bär', 'Baer'), isTrue);
    });

    test('punctuation and spaces fall away', () {
      expect(answersMatch('zu Hause!', 'zuhause'), isTrue);
    });

    test('blank input never counts', () {
      expect(answersMatch('', ''), isFalse);
      expect(answersMatch('!!!', 'Haus'), isFalse);
    });

    test('wrong stays wrong', () {
      expect(answersMatch('Maus', 'Haus'), isFalse);
    });
  });

  group('sorting', () {
    test('umlauts file under their base letter', () {
      final words = ['Zug', 'Baum', 'Bär', 'Öl', 'Ofen', 'Apfel']
        ..sort(compareDe);
      expect(words, ['Apfel', 'Bär', 'Baum', 'Ofen', 'Öl', 'Zug']);
    });

    test('sharp s counts as ss', () {
      final words = ['Fuß', 'Fussball', 'Futter']..sort(compareDe);
      expect(words, ['Fuß', 'Fussball', 'Futter']);
    });

    test('equal folding still orders stably', () {
      expect(compareDe('Bar', 'Bär'), isNot(0));
    });
  });

  group('api date', () {
    test('understands the space instead of T', () {
      expect(parseApiDate('2017-05-07 10:52:00'), DateTime(2017, 5, 7, 10, 52));
    });

    test('returns null on nonsense', () {
      expect(parseApiDate('nonsense'), isNull);
      expect(parseApiDate(null), isNull);
      expect(parseApiDate(''), isNull);
    });
  });

  group('relative time', () {
    final now = DateTime(2026, 8, 7, 12);

    test('past with the right inflection', () {
      expect(relativeTime('2026-08-06 12:00:00', now), 'vor 1 Tag');
      expect(relativeTime('2026-08-04 12:00:00', now), 'vor 3 Tagen');
      expect(relativeTime('2024-08-07 12:00:00', now), 'vor 2 Jahren');
    });

    test('future', () {
      expect(relativeTime('2026-08-09 12:00:00', now), 'in 2 Tagen');
    });

    test('just now instead of in 0 minutes', () {
      expect(relativeTime('2026-08-07 12:00:10', now), 'gerade eben');
    });

    test('half a unit stays in the smaller one', () {
      // Avoid rounding up to larger unit before threshold.
      expect(relativeTime('2026-07-22 12:00:00', now), 'vor 2 Wochen');
      expect(relativeTime('2026-02-07 12:00:00', now), 'vor 6 Monaten');
    });
  });

  group('intervals', () {
    final now = DateTime(2026, 8, 7, 12);

    test('rounds to a readable unit', () {
      expect(
        humanInterval(now.add(const Duration(minutes: 10)), now),
        '10 min',
      );
      expect(humanInterval(now.add(const Duration(hours: 5)), now), '5 h');
      expect(humanInterval(now.add(const Duration(days: 12)), now), '12 d');
      expect(humanInterval(now.add(const Duration(days: 200)), now), '7 mo');
      expect(humanInterval(now.add(const Duration(days: 730)), now), '2.0 a');
    });

    test('under a minute never becomes 0', () {
      expect(humanInterval(now.add(const Duration(seconds: 5)), now), '1 min');
    });

    test('eleven and a half months already read as a year', () {
      expect(humanInterval(now.add(const Duration(days: 350)), now), '1.0 a');
    });
  });
}
