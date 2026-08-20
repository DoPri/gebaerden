import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/ui/cards.dart';
import 'package:gebaerden/ui/widgets/entry_list.dart';
import 'package:gebaerden/ui/widgets/pieces.dart';
import 'package:integration_test/integration_test.dart';

import 'seed.dart';

/// Walks the app for the store preview video while `tools/preview.py` records
/// the screen:
///   flutter drive --profile --driver=test_driver/preview.dart \
///                 --target=test_driver/preview_test.dart
///
/// Profile, not debug, for two reasons. The build is compiled ahead of time
/// and a debug one dropped frames all through the film. And the pointer
/// crosshair the test binding draws over every tap sits inside an assert, so
/// it does not exist here, which is what makes it possible to tap and swipe on
/// camera at all. `tools/preview.py` draws a quiet ring in its place, from the
/// positions reported below.
///
/// The price is the keyboard: under profile the real one takes the text input
/// channel and enterText never reaches the field. So the tour browses by
/// letter instead of searching, which is a feature of its own.
///
/// The walk runs once unwatched and then again for the camera. Everything the
/// first pass touches is cached, so the filmed one never waits on the network.
/// Only the head and the tail are cut, what is reported here is one take.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  setUpAll(() async {
    (topic: _, settings: settings) = await seedStore();
    // The tour changes it on camera, so it starts where a new install starts.
    await settings.set('speed', 1.0);
    await settings.set('mirror', false);
  });

  tearDownAll(() => db.close());

  testWidgets('the tour', (tester) async {
    final taps = <Map<String, Object>>[];
    final ratio = tester.view.devicePixelRatio;
    var filming = false;

    // Short, this runs after every tap and a second each was most of the
    // length of the take.
    Future<void> settle() =>
        tester.pumpAndSettle(const Duration(milliseconds: 200));

    /// Real time only passes inside runAsync, and the whole point of the
    /// recording is what happens on screen while it does.
    ///
    /// fullyLive for the span, because the binding otherwise draws only the
    /// frames the test itself pumps. Everything the framework schedules on its
    /// own, the sign video and every scroll included, is dropped, and the
    /// recording came out as a row of stills. It goes back before pumping,
    /// since pumpAndSettle over a playing video finds no quiet frame.
    Future<void> live(Future<void> Function() body) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      await body();
      binding.framePolicy =
          LiveTestWidgetsFlutterBindingFramePolicy.fadePointers;
      await settle();
    }

    Future<void> hold(Duration span) =>
        live(() => tester.runAsync(() => Future<void>.delayed(span)));

    // Every tap leaves a beat. Chained back to back the tab changes went by
    // before the eye had followed them.
    Future<void> tap(
      Finder target, {
      Duration after = const Duration(milliseconds: 900),
    }) async {
      if (filming) {
        final centre = tester.getCenter(target);
        taps.add({
          'x': (centre.dx * ratio).round(),
          'y': (centre.dy * ratio).round(),
          'at': DateTime.now().millisecondsSinceEpoch,
        });
        // The mark goes on at that moment, so the screen being tapped has to
        // stay up long enough to see it. Without this beat the first cut was
        // over before the finger had landed.
        await hold(const Duration(milliseconds: 300));
      }
      await tester.tap(target);
      await settle();
      await hold(after);
    }

    /// A real flick, with the momentum that comes with it.
    Future<void> flick(double distance) => live(() async {
      await tester.fling(
        find.byType(Scrollable).hitTestable().first,
        Offset(0, -distance),
        1400,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
    });

    /// The answer options under a clip, without the credit links that sit with
    /// it. Both are Tappable and the licence line comes first in the tree,
    /// which is how the first pick opened creativecommons.org in a browser.
    Finder answer(Finder within) {
      final links = find
          .descendant(
            of: find.byType(LinkText),
            matching: find.byType(Tappable),
          )
          .evaluate()
          .toSet();
      final options = find
          .descendant(of: within, matching: find.byType(Tappable))
          .evaluate()
          .where((element) => !links.contains(element))
          .toList();
      if (options.isEmpty) throw StateError('nothing to answer with');
      return find.byWidget(options.first.widget);
    }

    final letter = find.descendant(
      of: find.byType(GridView),
      matching: find.text('H'),
    );

    /// The whole route once, so every clip, thumbnail and answer the filmed
    /// pass needs is already on the device.
    Future<void> warm() async {
      await tap(letter);
      await waitFor(tester, 'the letter list', find.byType(EntryRow));
      await waitForThumbnails(tester);
      await tap(find.byType(EntryRow).hitTestable().first);
      await hold(const Duration(seconds: 2));
      await tap(find.byTooltip('Zurück'));
      await tap(find.byTooltip('Zurück'));

      await tap(find.text('Lernen').last);
      await tap(find.text('Loslegen'));
      await waitFor(tester, 'the card', find.text('Welches Wort ist das?'));
      await hold(const Duration(seconds: 2));
      await tap(find.text('Beenden'), after: const Duration(seconds: 2));

      await reach(tester, find.text('Fingeralphabet'));
      await tap(find.text('Fingeralphabet'));
      await waitFor(
        tester,
        'the drill',
        find.text('Welcher Buchstabe ist das?'),
      );
      await hold(const Duration(seconds: 2));
      await tap(find.byTooltip('Zurück'));

      await tap(find.text('Wörterbuch').last);
    }

    await tester.pumpWidget(
      GebaerdenApp(db: db, settings: settings, network: NetworkStatus()),
    );
    await settle();
    await warm();
    await settings.set('speed', 1.0);
    await settings.set('mirror', false);
    await settle();

    filming = true;
    // Before the pause, not after it. Marking the start behind the hold cut
    // away the very second the letter grid was meant to be read in.
    final start = DateTime.now().millisecondsSinceEpoch;
    await hold(const Duration(milliseconds: 1200));

    await tap(letter, after: const Duration(milliseconds: 400));
    await waitFor(tester, 'the letter list', find.byType(EntryRow));
    await waitForThumbnails(tester);
    await flick(600);
    await flick(500);

    // hitTestable, the flicks above pushed the first row of the tree off
    // the top of the viewport and a tap there lands on nothing.
    await tap(
      find.byType(EntryRow).hitTestable().first,
      after: const Duration(seconds: 3),
    );
    await tap(
      find.byTooltip('Tempo'),
      after: const Duration(milliseconds: 900),
    );
    await tap(
      find.descendant(
        of: find.byType(PopupMenuItem<double>),
        matching: find.text('0,25x'),
      ),
      after: const Duration(milliseconds: 2600),
    );
    await tap(
      find.byTooltip('Spiegeln'),
      after: const Duration(milliseconds: 2200),
    );

    await tap(find.byTooltip('Zurück'));
    await tap(find.byTooltip('Zurück'));
    // Back to normal before practising. The trainer is not the place to show
    // off slow motion, and a mirrored signer there only confuses.
    await settings.set('speed', 1.0);
    await settings.set('mirror', false);
    await settle();
    await tap(find.text('Lernen').last, after: const Duration(seconds: 3));
    await tap(find.text('Loslegen'));
    await waitFor(tester, 'the card', find.text('Welches Wort ist das?'));
    await hold(const Duration(milliseconds: 2500));
    // Answering is the point of the trainer. Whichever option goes, the right
    // one turns green, so the beat reads either way.
    await tap(
      answer(find.byType(ChoiceCard)),
      after: const Duration(milliseconds: 2600),
    );

    await tap(find.text('Beenden'), after: const Duration(seconds: 2));
    await tap(
      find.text('Fingeralphabet'),
      after: const Duration(milliseconds: 2200),
    );
    await tap(
      answer(find.byType(Wrap)),
      after: const Duration(milliseconds: 2400),
    );

    await tap(find.byTooltip('Zurück'));
    // No reach before either of these. Both sit on the screen as it opens and
    // scrollUntilVisible put a jump in the film ahead of the tap.
    await tap(find.text('Mehr').last, after: const Duration(seconds: 2));
    await tap(
      find.text('Gebärden herunterladen'),
      after: const Duration(milliseconds: 900),
    );
    // No scrolling here. The letter grid and the package rows share the
    // screen, so the tap and everything it sets off are in view at once.
    // X carries few words, so the package is through while the film is still
    // on it and the row shows the whole run rather than a frozen bar.
    await tap(
      find.descendant(of: find.byType(Wrap), matching: find.text('X')),
      after: const Duration(seconds: 5),
    );

    binding.reportData = {
      'start': start,
      'end': DateTime.now().millisecondsSinceEpoch,
      'taps': taps,
      // The system bars are not part of the app and have no business in a
      // store video. screenrecord films them, so their heights go over and
      // ffmpeg crops them off.
      'top': tester.view.viewPadding.top.round(),
      'bottom': tester.view.viewPadding.bottom.round(),
    };
  });
}
