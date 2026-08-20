import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/platform/notify.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/ui/tour.dart';
import 'package:gebaerden/ui/widgets/sign_video.dart';
import 'package:http/http.dart' as http;

import 'channels.dart';
import 'fake_storage.dart';
import 'fake_video.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;

  setUpAll(() {
    FileDownloader(persistentStorage: MemoryStorage());
  });

  setUp(() async {
    db = testDb();
    channels = FakeChannels()..install();
    FakeVideoPlayer().install();
    downloads = Downloads(db);
    await initNotifications();
    // Stubs empty index to immediately end startup sync, plus entry mock for video step.
    stubApi({
      'index': <Object>[],
      'entry': {'id': 1, 'text': 'Hallo', 'currentVideo': sampleVideo.toJson()},
    });
  });

  tearDown(() async {
    useClient(http.Client());
    channels.remove();
    await db.close();
  });

  /// Seeds cached entry with video for video tour step.
  Future<void> seed() async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
  }

  Future<void> boot(WidgetTester tester) async {
    final settings = AppSettings(db);
    await settings.load();
    await tester.pumpWidget(
      GebaerdenApp(db: db, settings: settings, network: NetworkStatus()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }
  }

  Future<bool> markerSet() async {
    final again = AppSettings(db);
    await again.load();
    return again.tourDone;
  }

  Rect? hole(WidgetTester tester) =>
      tester.widget<Spotlight>(find.byType(Spotlight)).hole;

  testWidgets('a first start opens the tour', (tester) async {
    await boot(tester);

    expect(find.text('Vier Bereiche'), findsOneWidget);
    expect(find.text('1 von ${tourSteps.length}'), findsOneWidget);
    expect(find.text('Weiter'), findsOneWidget);
    expect(find.text('Überspringen'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the spotlight sits on the widget the step talks about', (
    tester,
  ) async {
    await boot(tester);
    await next(tester);

    expect(find.text('Suchen'), findsOneWidget);
    expect(hole(tester), tester.getRect(find.byType(TextField)).inflate(6));
    await drain(tester);
  });

  testWidgets('the video step opens a sign and points at its controls', (
    tester,
  ) async {
    await seed();
    await boot(tester);
    await next(tester, 3);

    expect(find.text('Videos'), findsOneWidget);
    expect(find.byType(SignVideo), findsOneWidget);
    expect(hole(tester), isNotNull);
    expect(find.byTooltip('Endlosschleife'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('without a word to play the video step keeps its text', (
    tester,
  ) async {
    await boot(tester);
    await next(tester, 3);

    expect(find.text('Videos'), findsOneWidget);
    expect(find.byType(SignVideo), findsNothing);
    expect(hole(tester), isNull);
    await drain(tester);
  });

  testWidgets('the next step drops the sign again', (tester) async {
    await seed();
    await boot(tester);
    await next(tester, 4);

    expect(find.text('Trainer'), findsOneWidget);
    expect(find.byType(SignVideo), findsNothing);
    expect(find.text('FÄLLIG'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('every step lights up the widget it points at', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await seed();
    await boot(tester);

    for (final step in tourSteps) {
      expect(find.text(step.title), findsWidgets);
      expect(hole(tester), isNotNull, reason: step.title);
      if (step != tourSteps.last) await next(tester);
    }
    await drain(tester);
  });

  testWidgets('walking to the end marks the tour as seen', (tester) async {
    await boot(tester);
    await next(tester, tourSteps.length - 1);

    expect(find.text('Überspringen'), findsNothing);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    expect(find.byType(Spotlight), findsNothing);
    expect(await markerSet(), isTrue);
    expect(find.text('NACH BUCHSTABE'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('skipping ends the tour and it stays gone', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();

    expect(find.byType(Spotlight), findsNothing);
    expect(await markerSet(), isTrue);

    await boot(tester);
    expect(find.byType(Spotlight), findsNothing);
    await drain(tester);
  });

  testWidgets('a seen tour does not open again', (tester) async {
    await tourSeen(db);
    await boot(tester);

    expect(find.byType(Spotlight), findsNothing);
    expect(find.text('NACH BUCHSTABE'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('Mehr starts the tour over', (tester) async {
    // Viewport height avoids scrolling to access tour restart button.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tourSeen(db);
    await boot(tester);

    await tester.tap(find.text('Mehr').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rundgang erneut ansehen'));
    await tester.pumpAndSettle();

    expect(find.text('Vier Bereiche'), findsOneWidget);
    expect(await markerSet(), isFalse);

    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    expect(find.text('Rundgang erneut ansehen'), findsOneWidget);
    await drain(tester);
  });
}
