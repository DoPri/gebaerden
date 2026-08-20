import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/ui/widgets/sign_video.dart';
import 'package:video_player/video_player.dart';

import 'channels.dart';
import 'fake_video.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late FakeVideoPlayer player;
  late Directory tmp;

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
    player = FakeVideoPlayer()..install();
    tmp = Directory.systemTemp.createTempSync('video_test');
  });

  tearDown(() async {
    channels.remove();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> open(
    WidgetTester tester, {
    ApiVideo video = sampleVideo,
    bool controls = true,
    bool? loop,
    bool compact = false,
    VoidCallback? onEnded,
  }) async {
    await tester.pumpWidget(
      await harness(
        db,
        ListView(
          children: [
            SignVideo(
              db: db,
              video: video,
              label: 'Haus',
              controls: controls,
              loop: loop,
              compact: compact,
              onEnded: onEnded,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the clip is opened muted and starts by itself', (tester) async {
    await open(tester);

    expect(player.opened.single.uri, sampleVideo.videoUrl);
    expect(player.calls, contains('setVolume:0.0'));
    expect(player.calls, contains('play'));
    expect(find.byType(VideoPlayer), findsOneWidget);
  });

  testWidgets('a clip that arrives after the word changed is dropped', (
    tester,
  ) async {
    const next = ApiVideo(
      id: 952,
      videoUrl: 'https://assets.wishlephant.com/signdict/videos/y.mp4',
    );
    player.hold = true;
    await open(tester);
    await open(tester, video: next);
    player.release();
    // Event subscription cancellation requires real async clock before disposal.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(player.opened.map((d) => d.uri), [
      sampleVideo.videoUrl,
      next.videoUrl,
    ]);
    expect(player.calls.where((c) => c == 'dispose'), hasLength(1));
    expect(find.byType(VideoPlayer), findsOneWidget);
  });

  testWidgets('a stored file is played instead of the url', (tester) async {
    final file = File('${tmp.path}/951.mp4')..writeAsStringSync('x');
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Haus', currentVideo: sampleVideo),
    ]);
    await db
        .into(db.assets)
        .insert(
          StoredAsset(
            videoId: sampleVideo.id,
            kind: AssetKind.video,
            entryId: 1,
            localPath: file.path,
            bytes: 1,
            downloadedAt: DateTime.now(),
          ),
        );

    await open(tester);
    expect(player.opened.single.asset, isNull);
    expect(player.opened.single.uri, contains(file.path));
  });

  testWidgets('a broken clip leaves the poster up', (tester) async {
    final file = File('${tmp.path}/951.jpg')..writeAsBytesSync(onePixelPng);
    await db
        .into(db.assets)
        .insert(
          StoredAsset(
            videoId: sampleVideo.id,
            kind: AssetKind.thumbnail,
            entryId: 1,
            localPath: file.path,
            bytes: 1,
            downloadedAt: DateTime.now(),
          ),
        );

    player.broken = true;
    await open(tester);

    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the stored loop and speed are applied', (tester) async {
    final settings = AppSettings(db);
    await settings.load();
    await settings.set('loop', false);
    await settings.set('speed', 0.5);

    await open(tester);
    expect(player.calls, contains('setLooping:false'));
    expect(player.calls, contains('setPlaybackSpeed:0.5'));
  });

  testWidgets('a drill overrides the stored loop', (tester) async {
    await open(tester, loop: false);
    expect(player.calls, contains('setLooping:false'));
  });

  testWidgets('a new video opens a new player', (tester) async {
    await open(tester);
    const other = ApiVideo(id: 42, videoUrl: 'https://example.invalid/42.mp4');

    await open(tester, video: other);

    expect(player.opened, hasLength(2));
    expect(player.opened.last.uri, other.videoUrl);
  });

  testWidgets('a variant without a file drops the clip before it', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(VideoPlayer), findsOneWidget);

    // Clears player when new variant lacks video URL.
    await open(tester, video: const ApiVideo(id: 42));

    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('playing out calls back once', (tester) async {
    var ended = 0;
    await open(tester, loop: false, onEnded: () => ended++);

    player.finish(0);
    await tester.pumpAndSettle();
    player.finish(0);
    await tester.pumpAndSettle();

    expect(ended, 1);
  });

  testWidgets('a looping clip never counts as played out', (tester) async {
    var ended = 0;
    await open(tester, loop: true, onEnded: () => ended++);

    player.finish(0);
    await tester.pumpAndSettle();
    expect(ended, 0);
  });

  group('the controls', () {
    testWidgets('step back pauses and seeks', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Ein Bild zurück'));
      await tester.pumpAndSettle();

      expect(player.calls, contains('pause'));
      expect(player.calls, contains('seekTo:0'));
    });

    testWidgets('step forward moves one frame', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Ein Bild vor'));
      await tester.pumpAndSettle();

      expect(player.calls, contains('seekTo:40'));
    });

    testWidgets('play and pause switch', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(player.calls, contains('pause'));

      await tester.tap(find.byTooltip('Abspielen'));
      await tester.pumpAndSettle();
      expect(player.calls.where((c) => c == 'play'), hasLength(2));
    });

    testWidgets('the loop button reaches the player', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Endlosschleife'));
      await tester.pumpAndSettle();

      expect(player.calls, contains('setLooping:false'));

      final again = AppSettings(db);
      await again.load();
      expect(again.loop, isFalse);
    });

    testWidgets('the speed menu reaches the player', (tester) async {
      await open(tester);

      await tester.tap(find.text('1x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0,50x').last);
      await tester.pumpAndSettle();

      expect(player.calls, contains('setPlaybackSpeed:0.5'));
    });

    testWidgets('without a player the buttons are dead', (tester) async {
      player.broken = true;
      await open(tester, video: const ApiVideo(id: 7, videoUrl: 'x.mp4'));

      await tester.tap(find.byTooltip('Ein Bild vor'));
      await tester.pumpAndSettle();
      expect(player.calls, isNot(contains('seekTo:40')));
    });

    testWidgets('a drill can hide them', (tester) async {
      await open(tester, controls: false);
      expect(find.byTooltip('Abspielen'), findsNothing);
    });

    testWidgets('fullscreen keeps the same player', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Vollbild'));
      await tester.pumpAndSettle();

      expect(find.byType(FullscreenVideo), findsOneWidget);
      // Reuses controller to preserve playback position.
      expect(player.opened, hasLength(1));

      await tester.tap(find.byTooltip('Vollbild verlassen'));
      await tester.pumpAndSettle();
      expect(find.byType(FullscreenVideo), findsNothing);
    });
  });

  group('the credits', () {
    testWidgets('name the source and the license', (tester) async {
      await open(tester);
      expect(find.text('Wikisign DGS'), findsOneWidget);
      expect(find.textContaining('Lizenz:'), findsOneWidget);
    });

    testWidgets('link to the original when there is one', (tester) async {
      const video = ApiVideo(
        id: 7,
        videoUrl: 'https://example.invalid/7.mp4',
        originalHref: 'https://example.invalid/quelle',
      );
      await open(tester, video: video);
      expect(find.text('Originalquelle'), findsOneWidget);
    });

    testWidgets('stay quiet without a license', (tester) async {
      const video = ApiVideo(id: 7, videoUrl: 'https://example.invalid/7.mp4');
      await open(tester, video: video);
      expect(find.textContaining('Lizenz:'), findsNothing);
    });
  });

  testWidgets('a compact clip is capped in height', (tester) async {
    await open(tester, compact: true);

    final box = tester.widget<ConstrainedBox>(
      find
          .ancestor(
            of: find.byType(AspectRatio),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(box.constraints.maxHeight, lessThan(double.infinity));
  });
}
