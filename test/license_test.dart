import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/media/license.dart';

void main() {
  test('builds the label and the url from a CC path', () {
    final license = parseLicense('by-sa/3.0/de');
    expect(license!.label, 'CC BY-SA 3.0 DE');
    expect(license.url, 'https://creativecommons.org/licenses/by-sa/3.0/de/');
  });

  test('works without a jurisdiction', () {
    expect(parseLicense('by-nc-sa/4.0')!.label, 'CC BY-NC-SA 4.0');
  });

  test('tolerates stray slashes', () {
    expect(parseLicense('/by-sa/3.0/de/')!.label, 'CC BY-SA 3.0 DE');
  });

  test('returns null when there is nothing to show', () {
    expect(parseLicense(null), isNull);
    expect(parseLicense(''), isNull);
    expect(parseLicense('   '), isNull);
  });

  test('returns null when the version is missing', () {
    expect(parseLicense('by-sa'), isNull);
    expect(parseLicense('by-sa/'), isNull);
  });
}
