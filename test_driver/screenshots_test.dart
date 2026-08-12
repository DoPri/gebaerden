import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/api/queries.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:integration_test/integration_test.dart';

/// Takes the store screenshots on a device, light and dark:
///   flutter drive --driver=test_driver/screenshots.dart \
///                 --target=test_driver/screenshots_test.dart
///
/// It sits outside integration_test/ on purpose. takeScreenshot needs the
/// driver and a plain `flutter test integration_test` would fail on it.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppSettings settings;

  /// Real words off the live API, so the shots show what a user sees.
  Future<void> seed() async {
    final words = ['Haus', 'Hallo', 'Baum', 'Kind', 'Wasser', 'Freund'];
    for (final word in words) {
      final hits = await searchWord(word);
      final entry = hits.where((e) => e.currentVideo != null).firstOrNull;
      if (entry == null) continue;
      await cacheEntries(db, [entry]);
      await gradeCard(
        db,
        await getOrCreateCard(db, entry.id, Direction.recognition),
        f.Rating.good,
      );
    }
  }

  setUpAll(() async {
    // Android hands over frames only after the surface is converted.
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    downloads = Downloads(db);
    settings = AppSettings(db);
    await settings.load();
    await seed();
  });

  tearDown(() => db.close());

  Future<void> shoot(WidgetTester tester, ThemeMode mode, String suffix) async {
    // The system bars are not part of the captured surface, they leave an
    // empty strip that `tools/screenshots.py` cuts off. Their height rides along
    // in the file name, because takeScreenshot only accepts args on web.
    Future<void> shot(String name) => binding.takeScreenshot(
      '$name--top${tester.view.viewPadding.top.round()}'
      '--bottom${tester.view.viewPadding.bottom.round()}',
    );

    /// pumpAndSettle takes an interval, not a wait. Real time only passes
    /// inside runAsync, and the clip needs some to decode its first frame.
    Future<void> breathe() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      await tester.pumpAndSettle();
    }

    await settings.setThemeMode(mode);
    final network = NetworkStatus();
    await tester.pumpWidget(
      GebaerdenApp(db: db, settings: settings, network: network),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await shot('01-woerterbuch-$suffix');

    await tester.tap(find.text('Lernen').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await shot('02-trainer-$suffix');

    await tester.tap(find.text('Fingeralphabet'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await breathe();
    await shot('03-fingeralphabet-$suffix');

    // The drill is pushed outside the tab shell, so the tabs are gone until
    // it is popped again.
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('Mehr').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await shot('04-mehr-$suffix');
  }

  testWidgets('light', (tester) => shoot(tester, ThemeMode.light, 'hell'));
  testWidgets('dark', (tester) => shoot(tester, ThemeMode.dark, 'dunkel'));
}
