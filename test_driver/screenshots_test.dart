import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/ui/widgets/entry_list.dart';
import 'package:integration_test/integration_test.dart';

import 'seed.dart';

/// Takes the store screenshots on a device:
///   flutter drive --driver=test_driver/screenshots.dart \
///                 --target=test_driver/screenshots_test.dart
///
/// It sits outside integration_test/ on purpose. takeScreenshot needs the
/// driver and a plain `flutter test integration_test` would fail on it.
///
/// Eight frames, one feature each, since Play takes eight per locale and a
/// second theme would spend half of them on a screen that is already there.
/// `tools/screenshots.py` crops, captions and files them.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;
  late StoredList topic;

  setUpAll(() async {
    // Android hands over frames only after the surface is converted.
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    (topic: topic, settings: settings) = await seedStore();
  });

  tearDownAll(() => db.close());

  testWidgets('the store set', (tester) async {
    var taken = 0;

    // The system bars are not part of the captured surface, they leave an
    // empty strip that `tools/screenshots.py` cuts off. Their height rides
    // along in the file name, because takeScreenshot only accepts args on web.
    Future<void> shot(String name) => binding.takeScreenshot(
      '${(++taken).toString().padLeft(2, '0')}-$name'
      '-${settings.themeMode == ThemeMode.dark ? 'dunkel' : 'hell'}'
      '--top${tester.view.viewPadding.top.round()}'
      '--bottom${tester.view.viewPadding.bottom.round()}',
    );

    Future<void> settle() => tester.pumpAndSettle(const Duration(seconds: 2));

    /// pumpAndSettle takes an interval, not a wait. Real time only passes
    /// inside runAsync, and a clip needs some to decode its first frame.
    Future<void> breathe() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      await settle();
    }

    Future<void> tap(Finder target) async {
      await tester.tap(target);
      await settle();
    }

    Future<void> back() => tap(find.byTooltip('Zurück'));

    await tester.pumpWidget(
      GebaerdenApp(db: db, settings: settings, network: NetworkStatus()),
    );
    await settle();

    await tester.enterText(find.byType(TextField).first, 'Haus');
    await settle();
    await waitFor(tester, 'the search results', find.byType(EntryRow));
    await waitForThumbnails(tester);
    await breathe();
    await shot('woerterbuch');

    await tap(find.byType(EntryRow).first);
    await breathe();
    await tap(find.byTooltip('Tempo'));
    await shot('video');
    await tap(
      find.descendant(
        of: find.byType(PopupMenuItem<double>),
        matching: find.text('0,25x'),
      ),
    );
    await back();

    await tap(find.text('Lernen').last);
    await shot('lernen');

    await tap(find.text('Loslegen'));
    await waitFor(tester, 'the card', find.text('Welches Wort ist das?'));
    await breathe();
    await shot('abfrage');
    await tap(find.text('Beenden'));

    await reach(tester, find.text('Fingeralphabet'));
    await tap(find.text('Fingeralphabet'));
    await waitFor(tester, 'the drill', find.text('Welcher Buchstabe ist das?'));
    await breathe();
    await shot('fingeralphabet');
    await back();

    await tap(find.text('Listen').last);
    await tap(find.text(topic.name).first);
    await shot('liste');
    await back();

    await tap(find.text('Mehr').last);
    await shot('statistik');

    await settings.setThemeMode(ThemeMode.dark);
    await settle();
    await reach(tester, find.text('Gebärden herunterladen'));
    await tap(find.text('Gebärden herunterladen'));
    await shot('offline');
  });
}
