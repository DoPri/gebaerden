import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart' as data;
import 'package:gebaerden/db/database.dart' show ApiVideo;
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/media/media.dart';
import 'package:gebaerden/platform/notify.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/srs/charset.dart';
import 'package:gebaerden/theme.dart';
import 'package:gebaerden/transfer/backup.dart';
import 'package:gebaerden/ui/charset_screen.dart';
import 'package:gebaerden/ui/dictionary_screen.dart';
import 'package:gebaerden/ui/more_screen.dart';
import 'package:gebaerden/ui/widgets/entry_list.dart';
import 'package:gebaerden/ui/widgets/pieces.dart';
import 'package:gebaerden/ui/widgets/sign_video.dart';
import 'package:gebaerden/ui/widgets/variant_list.dart';
import 'package:http/http.dart' as http;

import 'channels.dart';
import 'fake_video.dart';
import 'harness.dart';
import 'support.dart';

/// The corners the ordinary walk through the app never reaches.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late data.AppDatabase db;
  late FakeChannels channels;
  late FakeVideoPlayer video;
  late Directory tmp;

  setUp(() {
    db = testDb();
    // The screens reach the database through this in the running app.
    data.db = db;
    channels = FakeChannels()..install();
    video = FakeVideoPlayer()..install();
    tmp = Directory.systemTemp.createTempSync('edges_test');
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    useClient(http.Client());
    channels.remove();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// A file that is not an image, so decoding it has to fail.
  File brokenImage(String name) =>
      File('${tmp.path}/$name')..writeAsStringSync('kein bild');

  Future<void> storeThumb(File file) => db
      .into(db.assets)
      .insert(
        data.StoredAsset(
          videoId: sampleVideo.id,
          kind: data.AssetKind.thumbnail,
          entryId: 1,
          localPath: file.path,
          bytes: 1,
          downloadedAt: DateTime.now(),
        ),
      );

  // The decoder never runs in a widget test, so this only shows that a row
  // with a broken file still builds. The fallback itself is checked on device.
  group('a thumbnail that will not decode', () {
    testWidgets('leaves the placeholder in the list', (tester) async {
      final rows = await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      ]);
      await storeThumb(brokenImage('kaputt.jpg'));

      await tester.pumpWidget(
        await harness(db, EntryListView(db: db, entries: rows, onOpen: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EntryRow), findsOneWidget);
      await drain(tester);
    });

    testWidgets('leaves the variant row empty', (tester) async {
      await storeThumb(brokenImage('kaputt2.jpg'));

      await tester.pumpWidget(
        await harness(
          db,
          VariantList(
            db: db,
            videos: const [sampleVideo],
            selected: sampleVideo.id,
            word: 'Hallo',
            onSelect: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VariantList), findsOneWidget);
      await drain(tester);
    });
  });

  testWidgets('a clip torn down while it opens is let go', (tester) async {
    await tester.pumpWidget(
      await harness(db, SignVideo(db: db, video: sampleVideo, label: 'Haus')),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(find.byType(SignVideo), findsNothing);
    await drain(tester);
  });

  testWidgets('the search shows the cache before the server answers', (
    tester,
  ) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Haus', currentVideo: sampleVideo),
    ]);
    // Never answers, so only the cached hits can show up.
    useClient(_SilentClient());

    await tester.pumpWidget(await harness(db, DictionaryScreen(db: db)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Haus');
    await settle(tester);

    expect(find.widgetWithText(EntryRow, 'Haus'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await drain(tester);
  });

  group('the spelling drill', () {
    Future<void> open(WidgetTester tester) async {
      await cacheEntries(db, [
        sampleEntry(id: 900, text: 'Baba', currentVideo: sampleVideo),
      ]);
      stubEcho();

      await tester.pumpWidget(
        await harness(db, CharsetScreen(db: db, charset: Charset.alphabet)),
      );
      await settle(tester, steps: 20);
      await tester.tap(find.text('Buchstabieren'));
      await settle(tester);
    }

    testWidgets('takes the answer on the enter key', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Baba');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, steps: 2);

      expect(find.text('Richtig.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('can play the word again from the start', (tester) async {
      await open(tester);
      expect(find.text('Buchstabe 1 von 4'), findsOneWidget);

      video.finish(video.opened.length - 1);
      await settle(tester);
      expect(find.text('Buchstabe 2 von 4'), findsOneWidget);

      await tester.tap(find.text('Nochmal zeigen'));
      await settle(tester);

      expect(find.text('Buchstabe 1 von 4'), findsOneWidget);
      await drain(tester);
    });
  });

  testWidgets('a backup that is not even text says so', (tester) async {
    // Half a utf-8 sequence. The decoder replaces it, and the JSON parser is
    // the one who complains, with a friendly message.
    final file = File('${tmp.path}/kaputt.json')
      ..writeAsBytesSync([0x7b, 0xc3]);
    channels.pick = file.path;

    await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Importieren'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Importieren'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Die Datei ist kein gültiges JSON.'), findsOneWidget);
    await drain(tester);
  });

  group('on iOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FlutterLocalNotificationsPlatform.instance =
          IOSFlutterLocalNotificationsPlugin();
    });

    tearDown(() {
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
    });

    test('the reminder asks the way iOS wants it', () async {
      await initNotifications();
      expect(
        await scheduleReminders(const [
          (
            reminder: Reminder(
              days: {1, 2, 3, 4, 5, 6, 7},
              hour: 19,
              minute: 0,
            ),
            listId: 'kueche',
            due: 2,
          ),
        ]),
        isTrue,
      );

      expect(
        channels.calls,
        contains(
          'dexterous.com/flutter/local_notifications.requestPermissions',
        ),
      );
      expect(channels.scheduled, hasLength(1));
    });

    test('a refusal comes back as false', () async {
      channels.notificationsAllowed = false;
      expect(
        await scheduleReminders(const [
          (
            reminder: Reminder(
              days: {1, 2, 3, 4, 5, 6, 7},
              hour: 19,
              minute: 0,
            ),
            listId: 'kueche',
            due: 2,
          ),
        ]),
        isFalse,
      );
      expect(channels.scheduled, isEmpty);
    });
  });

  group('the accent', () {
    test('any color is pushed until it carries text', () {
      for (final wanted in [
        0xFFFFFFFF,
        0xFF000000,
        0xFFFFFF00,
        0xFF00FF00,
        0xFF955E11,
      ]) {
        for (final base in [AppColors.light, AppColors.dark]) {
          final made = accented(base, wanted);
          final on = made.accent.computeLuminance() + 0.05;
          final bg = base.bg.computeLuminance() + 0.05;
          expect(on > bg ? on / bg : bg / on, greaterThanOrEqualTo(4.5));
        }
      }
    });

    test('a color that already fits is left alone', () {
      expect(
        accented(AppColors.light, defaultAccent).accent,
        const Color(defaultAccent),
      );
    });

    test('reaches the theme in both brightnesses', () {
      const wanted = 0xFF3C6B57;
      final light = appTheme(Brightness.light, wanted);
      final dark = appTheme(Brightness.dark, wanted);

      expect(light.extension<AppColors>()!.accent, const Color(wanted));
      expect(dark.extension<AppColors>()!.accent, isNot(const Color(wanted)));
      // Everything else stays as it was.
      expect(light.extension<AppColors>()!.bg, AppColors.light.bg);
    });

    testWidgets('a suggestion sticks', (tester) async {
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Salbei'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.bySemanticsLabel('Salbei'));
      await tester.pumpAndSettle();

      final settings = AppSettings(db);
      await settings.load();
      expect(settings.accent, 0xFF3C6B57);
      await drain(tester);
    });

    testWidgets('a free color comes back from the dialog', (tester) async {
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Eigene Farbe'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.bySemanticsLabel('Eigene Farbe'));
      await tester.pumpAndSettle();
      expect(find.byType(ColorPicker), findsOneWidget);

      // Drag the saturation area, which is what a free pick amounts to.
      final area = tester.getRect(find.byType(ColorPicker));
      await tester.tapAt(Offset(area.left + 20, area.top + 20));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      final settings = AppSettings(db);
      await settings.load();
      expect(settings.accent, isNot(defaultAccent));
      await drain(tester);
    });

    testWidgets('backing out keeps the old one', (tester) async {
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Eigene Farbe'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.bySemanticsLabel('Eigene Farbe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      final settings = AppSettings(db);
      await settings.load();
      expect(settings.accent, defaultAccent);
      await drain(tester);
    });
  });

  test('a color scheme can be nudged one value at a time', () {
    const other = Color(0xFF123456);

    final tinted = AppColors.light.copyWith(accent: other);
    expect(tinted.accent, other);
    expect(tinted.bg, AppColors.light.bg);

    // The other way round, so every fallback is taken once.
    final swapped = AppColors.light.copyWith(bg: other);
    expect(swapped.bg, other);
    expect(swapped.accent, AppColors.light.accent);
  });

  testWidgets('a hair line is just a line', (tester) async {
    await tester.pumpWidget(await harness(db, HairLine(key: UniqueKey())));
    await tester.pumpAndSettle();

    expect(find.byType(HairLine), findsOneWidget);
    await drain(tester);
  });

  test('the exported schema is the one the importer looks for', () {
    expect(backupSchema, 'signdict-trainer/v2');
  });

  test('a media source without anything to play is null', () async {
    expect(
      await resolveMedia(db, const ApiVideo(id: 1), data.AssetKind.video),
      isNull,
    );
  });
}

/// Takes the request and never answers, so only the cache can fill the screen.
class _SilentClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}
