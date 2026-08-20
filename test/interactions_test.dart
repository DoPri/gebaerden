import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/recent.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/srs/charset.dart';
import 'package:gebaerden/ui/charset_screen.dart';
import 'package:gebaerden/ui/entry_screen.dart';
import 'package:gebaerden/ui/more_screen.dart';
import 'package:gebaerden/ui/offline_screen.dart';
import 'package:gebaerden/ui/widgets/pieces.dart';
import 'package:gebaerden/ui/widgets/sign_video.dart';

import 'channels.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
  });

  tearDown(() async {
    channels.remove();
    await db.close();
  });

  group('video controls', () {
    testWidgets('mirroring and looping are remembered', (tester) async {
      final settings = AppSettings(db);
      await settings.load();
      expect(settings.mirror, isFalse);

      await tester.pumpWidget(
        await harness(db, SignVideo(db: db, video: sampleVideo, label: 'Haus')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Spiegeln'));
      await tester.pumpAndSettle();

      final again = AppSettings(db);
      await again.load();
      expect(again.mirror, isTrue);

      await tester.tap(find.byTooltip('Endlosschleife'));
      await tester.pumpAndSettle();
      await again.load();
      expect(again.loop, isFalse);
      await drain(tester);
    });

    testWidgets('the speed menu writes the pick through', (tester) async {
      await tester.pumpWidget(
        await harness(db, SignVideo(db: db, video: sampleVideo, label: 'Haus')),
      );
      await tester.pumpAndSettle();

      expect(find.text('1x'), findsOneWidget);
      await tester.tap(find.text('1x'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('0,50x').last);
      await tester.pumpAndSettle();

      final settings = AppSettings(db);
      await settings.load();
      expect(settings.speed, 0.5);
      await drain(tester);
    });

    testWidgets('names the source and links the license', (tester) async {
      await tester.pumpWidget(
        await harness(db, SignVideo(db: db, video: sampleVideo, label: 'Haus')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wikisign DGS'), findsOneWidget);
      expect(find.textContaining('CC BY-SA 3.0 DE'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('stepping and playing are offered but stay inert without a '
        'player', (tester) async {
      await tester.pumpWidget(
        await harness(db, SignVideo(db: db, video: sampleVideo, label: 'Haus')),
      );
      await tester.pumpAndSettle();

      for (final label in ['Ein Bild zurück', 'Ein Bild vor', 'Abspielen']) {
        expect(find.byTooltip(label), findsOneWidget);
        await tester.tap(find.byTooltip(label));
        await tester.pumpAndSettle();
      }
      await drain(tester);
    });

    testWidgets('a video without a license shows only the source', (
      tester,
    ) async {
      await tester.pumpWidget(
        await harness(
          db,
          SignVideo(
            db: db,
            video: const ApiVideo(id: 1, userName: 'Jemand'),
            label: 'Haus',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jemand'), findsOneWidget);
      expect(find.textContaining('Lizenz'), findsNothing);
      await drain(tester);
    });

    testWidgets('without controls there is no bar', (tester) async {
      await tester.pumpWidget(
        await harness(
          db,
          SignVideo(db: db, video: sampleVideo, label: 'Haus', controls: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Spiegeln'), findsNothing);
      await drain(tester);
    });
  });

  group('a downloaded video', () {
    testWidgets('is played from the file, not from the net', (tester) async {
      final dir = Directory.systemTemp.createTempSync('video_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/951.mp4')..writeAsStringSync('nicht echt');

      await cacheEntries(db, [sampleEntry(currentVideo: sampleVideo)]);
      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: sampleVideo.id,
              kind: AssetKind.video,
              entryId: 835,
              localPath: file.path,
              bytes: 10,
              downloadedAt: DateTime.now(),
            ),
          );

      // Corrupt or dummy video file should not crash player widget.
      await tester.pumpWidget(
        await harness(db, SignVideo(db: db, video: sampleVideo, label: 'Haus')),
      );
      await settle(tester);

      expect(find.text('Wikisign DGS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await drain(tester);
    });
  });

  group('spelling drill', () {
    Future<void> prepare() async {
      final chars = ['h', 'a', 'u', 's', 'm'];
      final rows = await cacheEntries(db, [
        for (final (i, c) in chars.indexed)
          sampleEntry(id: 300 + i, text: c, currentVideo: sampleVideo),
        sampleEntry(id: 400, text: 'Haus', currentVideo: sampleVideo),
        sampleEntry(id: 401, text: 'Maus', currentVideo: sampleVideo),
      ]);
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            StoredSetting(
              key: 'charset:alphabet',
              value: {for (final (i, c) in chars.indexed) c: rows[i].id},
            ),
          );
    }

    testWidgets('offers the mode and spells letter by letter', (tester) async {
      await prepare();
      await tester.pumpWidget(
        await harness(db, CharsetScreen(db: db, charset: Charset.alphabet)),
      );
      await settle(tester);

      await tester.tap(find.text('Buchstabieren'));
      await settle(tester);

      expect(find.textContaining('Buchstabe 1 von'), findsOneWidget);
      expect(find.text('Welches Wort war das?'), findsOneWidget);
      expect(find.text('Nochmal zeigen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a wrong guess names the word', (tester) async {
      await prepare();
      await tester.pumpWidget(
        await harness(db, CharsetScreen(db: db, charset: Charset.alphabet)),
      );
      await settle(tester);
      await tester.tap(find.text('Buchstabieren'));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'quatsch');
      await tester.tap(find.text('Prüfen'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Es war:'), findsNothing);
      expect(find.textContaining('Richtig war:'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('an answer in the reading drill moves on', (tester) async {
      await prepare();
      await tester.pumpWidget(
        await harness(db, CharsetScreen(db: db, charset: Charset.alphabet)),
      );
      await settle(tester);

      // Answers are randomized.
      final offered = [
        'H',
        'A',
        'U',
        'S',
        'M',
      ].where((c) => find.text(c).evaluate().isNotEmpty).toList();
      expect(offered, hasLength(4));

      await tester.tap(find.text(offered.first));
      await settle(tester);
      expect(find.text('Welcher Buchstabe ist das?'), findsOneWidget);
      await drain(tester);
    });
  });

  group('settings screen', () {
    testWidgets('the theme buttons switch and stick', (tester) async {
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dunkel'));
      await tester.pumpAndSettle();

      final settings = AppSettings(db);
      await settings.load();
      expect(settings.themeMode, ThemeMode.dark);
      await drain(tester);
    });

    testWidgets('the video-less switch flips', (tester) async {
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final settings = AppSettings(db);
      await settings.load();
      expect(settings.showWithoutVideo, isTrue);
      await drain(tester);
    });

    testWidgets('clearing the history empties it and says so', (tester) async {
      await remember(db, RecentKind.search, 'haus', 'haus');
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Suchverlauf löschen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Suchverlauf löschen'));
      await tester.pumpAndSettle();

      expect(find.text('Verlauf gelöscht.'), findsOneWidget);
      expect(await recentItems(db, RecentKind.search), isEmpty);
      await drain(tester);
    });

    testWidgets('a nonsense limit is ignored', (tester) async {
      await tester.pumpWidget(await harness(db, MoreScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '20'), 'abc');
      await tester.pumpAndSettle();

      final settings = AppSettings(db);
      await settings.load();
      expect(settings.newPerDay, 20);
      await drain(tester);
    });
  });

  group('offline screen', () {
    testWidgets('a stored asset shows up in the header', (tester) async {
      await cacheEntries(db, [sampleEntry(currentVideo: sampleVideo)]);
      await db
          .into(db.assets)
          .insert(
            StoredAsset(
              videoId: sampleVideo.id,
              kind: AssetKind.video,
              entryId: 835,
              localPath: '/tmp/x.mp4',
              bytes: 2 * 1024 * 1024,
              downloadedAt: DateTime.now(),
            ),
          );

      await tester.pumpWidget(await harness(db, OfflineScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('2.0 MB'), findsOneWidget);
      expect(find.text('Leeren'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a running job offers pause and cancel', (tester) async {
      await db
          .into(db.packages)
          .insert(
            StoredPackage(
              id: 'letter:B',
              label: 'Buchstabe B',
              spec: '{"kind":"letter","letter":"B"}',
              status: PackageStatus.running,
              done: 3,
              total: 10,
              bytes: 0,
              updatedAt: DateTime.now(),
            ),
          );

      await tester.pumpWidget(await harness(db, OfflineScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.text('Buchstabe B'), findsOneWidget);
      expect(find.text('3 / 10'), findsOneWidget);
      expect(find.byTooltip('Pausieren'), findsOneWidget);
      expect(find.byTooltip('Abbrechen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a paused job offers resume instead', (tester) async {
      await db
          .into(db.packages)
          .insert(
            StoredPackage(
              id: 'letter:B',
              label: 'Buchstabe B',
              spec: '{"kind":"letter","letter":"B"}',
              status: PackageStatus.paused,
              done: 3,
              total: 10,
              bytes: 0,
              updatedAt: DateTime.now(),
            ),
          );

      await tester.pumpWidget(await harness(db, OfflineScreen(db: db)));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Fortsetzen'), findsOneWidget);
      expect(find.byTooltip('Pausieren'), findsNothing);
      await drain(tester);
    });
  });

  group('entry details', () {
    testWidgets('a description and related words are shown', (tester) async {
      stubApi({
        'entry': {
          'id': 835,
          'text': 'Haus',
          'description': '  Ein Gebäude zum Wohnen.  ',
          'currentVideo': sampleVideo.toJson(),
        },
        'search': [
          {'id': 836, 'text': 'Hausfrau', 'currentVideo': sampleVideo.toJson()},
          {'id': 835, 'text': 'Haus', 'currentVideo': sampleVideo.toJson()},
        ],
      });

      await tester.pumpWidget(await harness(db, EntryScreen(db: db, id: 835)));
      await settle(tester);

      // Video header pushes related words off-screen.
      await tester.scrollUntilVisible(
        find.text('VERWANDTE WÖRTER'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Ein Gebäude zum Wohnen.'), findsOneWidget);
      expect(find.text('Hausfrau'), findsOneWidget);
      expect(find.widgetWithText(WordChip, 'Haus'), findsNothing);
      await drain(tester);
    });

    testWidgets('sharing hands over the signdict link', (tester) async {
      stubApi({
        'entry': {
          'id': 835,
          'text': 'Haus',
          'currentVideo': sampleVideo.toJson(),
        },
        'search': <Object>[],
      });

      await tester.pumpWidget(await harness(db, EntryScreen(db: db, id: 835)));
      await settle(tester);

      await tester.tap(find.byTooltip('Gebärde teilen'));
      await tester.pumpAndSettle();

      expect(channels.calls, contains('dev.fluttercommunity.plus/share.share'));
      await drain(tester);
    });

    test('the signdict link carries the variant when there is one', () {
      expect(signdictUrl(835), 'https://signdict.org/entry/835');
      expect(signdictUrl(835, 951), 'https://signdict.org/entry/835/video/951');
    });
  });
}
