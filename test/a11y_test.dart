import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/theme.dart';
import 'package:gebaerden/ui/widgets/pieces.dart';

Widget _sample(Brightness brightness, [int accent = defaultAccent]) {
  return MaterialApp(
    theme: appTheme(brightness, accent),
    home: Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.bg,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionLabel('Tageslimits'),
            const Text('Wörter, die du achtmal vergessen hast.'),
            const Note('Dazu haben wir nichts gefunden.'),
            const Note('Die Suche hat nicht funktioniert.', problem: true),
            AppButton(label: 'Loslegen', filled: true, onPressed: () {}),
            AppButton(label: 'Offline speichern', onPressed: () {}),
            AppButton(label: 'Leeren', danger: true, onPressed: () {}),
            ChoiceRow(
              label: 'Abfrageart',
              options: const [(1, 'Selbst'), (2, 'Auswahl'), (3, 'Tippen')],
              value: 1,
              onChanged: (_) {},
            ),
            const TextField(
              decoration: InputDecoration(hintText: 'Wort eintippen'),
            ),
            Wrap(
              spacing: 6,
              children: [
                WordChip('Hausfrau', onTap: () {}),
                WordChip('Rathaus', onTap: () {}),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      testWidgets('text meets the contrast guideline', (tester) async {
        await tester.pumpWidget(_sample(brightness));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });

      testWidgets('tap targets are big enough', (tester) async {
        await tester.pumpWidget(_sample(brightness));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      });

      testWidgets('tap targets carry a label', (tester) async {
        await tester.pumpWidget(_sample(brightness));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });

      // Whatever the picker hands over has to stay readable. The suggestions
      // carry German names on screen, so the hex is what names the case here.
      for (final color in [
        ...suggestedAccents.map((accent) => accent.$1),
        0xFFFFFFFF,
        0xFF000000,
        0xFFFFFF00,
        0xFF00FF00,
        0xFFFF00FF,
      ]) {
        testWidgets('accent ${color.toRadixString(16)} stays readable', (
          tester,
        ) async {
          await tester.pumpWidget(_sample(brightness, color));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        });
      }
    });
  }
}
