import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/packages/manager.dart';

void main() {
  group('package spec', () {
    test('every kind survives a round trip', () {
      const specs = [
        AllPackage(),
        LetterPackage('B'),
        ListPackage('abc', 'Küche'),
        EntryPackage(42, 'Haus'),
      ];

      for (final spec in specs) {
        final back = PackageSpec.fromJson(
          jsonDecode(jsonEncode(spec.toJson())) as Map<String, dynamic>,
        );
        expect(back.id, spec.id);
        expect(back.label, spec.label);
      }
    });

    test('ids stay apart across kinds', () {
      final ids = {
        const AllPackage().id,
        const LetterPackage('B').id,
        const ListPackage('B', 'x').id,
        const EntryPackage(1, 'x').id,
      };
      expect(ids, hasLength(4));
    });

    test('an unknown kind falls back instead of throwing', () {
      expect(PackageSpec.fromJson({'kind': 'etwas-neues'}), isA<AllPackage>());
    });

    test('the label is what the notification shows', () {
      expect(const LetterPackage('B').label, 'Buchstabe B');
      expect(const ListPackage('id', 'Küche').label, 'Küche');
      expect(const EntryPackage(1, 'Haus').label, 'Haus');
    });
  });
}
