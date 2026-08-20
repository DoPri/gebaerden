import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/srs/charset.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/ui/cards.dart';
import 'package:gebaerden/ui/charset_screen.dart';
import 'package:gebaerden/ui/learn_screen.dart';
import 'package:gebaerden/ui/lists_screen.dart';
import 'package:gebaerden/ui/widgets/sign_video.dart';
import 'package:http/http.dart' as http;

import 'channels.dart';
import 'fake_video.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late FakeVideoPlayer video;
  late Directory tmp;

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
    video = FakeVideoPlayer()..install();
    tmp = Directory.systemTemp.createTempSync('drills_test');
  });

  tearDown(() async {
    useClient(http.Client());
    channels.remove();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> seed(int count) async {
    await cacheEntries(db, [
      for (var i = 1; i <= count; i++)
        sampleEntry(id: i, text: 'Wort $i', currentVideo: sampleVideo),
    ]);
  }

  group('the trainer', () {
    testWidgets('the lobby counts what was learnt and takes it back', (
      tester,
    ) async {
      await seed(3);
      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loslegen'));
      await settle(tester);
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gut'));
      await settle(tester);
      await tester.tap(find.text('Beenden'));
      await settle(tester);

      expect(find.text('1 Karte gelernt.'), findsOneWidget);

      await tester.tap(find.byTooltip('Letzte Antwort zurücknehmen'));
      await settle(tester);

      expect(await db.select(db.reviews).get(), isEmpty);
      expect(find.text('Auflösen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the choice mode asks with four answers', (tester) async {
      final settings = AppSettings(db);
      await settings.load();
      await settings.set('mode', ReviewMode.choice.name);
      await seed(12);

      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loslegen'));
      await settle(tester);

      expect(find.byType(ChoiceCard), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the typing mode asks for the word', (tester) async {
      final settings = AppSettings(db);
      await settings.load();
      await settings.set('mode', ReviewMode.typing.name);
      await seed(3);

      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loslegen'));
      await settle(tester);

      expect(find.byType(TypingCard), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a wrong typed answer on the last card comes back', (
      tester,
    ) async {
      final settings = AppSettings(db);
      await settings.load();
      await settings.set('mode', ReviewMode.typing.name);
      await seed(1);

      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loslegen'));
      await settle(tester);
      expect(find.text('1 übrig'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'falsch');
      await tester.tap(find.text('Prüfen'));
      await settle(tester);

      expect(find.text('1 übrig'), findsOneWidget);
      expect(find.text('Prüfen'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await drain(tester);
    });

    testWidgets('a wrong choice on the last card comes back', (tester) async {
      final settings = AppSettings(db);
      await settings.load();
      await settings.set('mode', ReviewMode.choice.name);
      await seed(12);
      await addToList(db, knownList, [for (var i = 1; i <= 11; i++) i]);

      await tester.pumpWidget(await harness(db, LearnScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loslegen'));
      await settle(tester);
      expect(find.text('1 übrig'), findsOneWidget);

      final wrong = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((t) => RegExp(r'^Wort \d+$').hasMatch(t))
          .firstWhere((t) => t != 'Wort 12');
      await tester.tap(find.text(wrong));
      await settle(tester);

      expect(find.text('1 übrig'), findsOneWidget);
      await tester.tap(find.text('Wort 12'));
      await settle(tester);

      expect(find.text('2 Karten gelernt.'), findsOneWidget);
      await drain(tester);
    });
  });

  group('the cards', () {
    late List<CachedEntry> pool;

    setUp(() async {
      pool = await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Haus', currentVideo: sampleVideo),
        sampleEntry(id: 2, text: 'Baum', currentVideo: sampleVideo),
        sampleEntry(id: 3, text: 'Katze', currentVideo: sampleVideo),
        sampleEntry(id: 4, text: 'Hund', currentVideo: sampleVideo),
      ]);
    });

    CardProps props(int entryId, {ApiVideo? clip}) => CardProps(
      db: db,
      entry: pool.firstWhere((e) => e.id == entryId),
      card: newCard(entryId, Direction.recognition, DateTime.now()),
      video: clip,
      pool: pool,
      onAnswer: (_) {},
    );

    testWidgets('the next word hides the answer again', (tester) async {
      await tester.pumpWidget(await harness(db, SelfRatedCard(props(1))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();
      expect(find.text('Haus'), findsOneWidget);

      await tester.pumpWidget(await harness(db, SelfRatedCard(props(2))));
      await tester.pumpAndSettle();

      expect(find.text('Auflösen'), findsOneWidget);
      expect(find.text('Baum'), findsNothing);
      await drain(tester);
    });

    testWidgets('the next word clears the typed answer', (tester) async {
      await tester.pumpWidget(await harness(db, TypingCard(props(1))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Baum');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Richtig ist: Haus'), findsOneWidget);

      await tester.pumpWidget(await harness(db, TypingCard(props(2))));
      await tester.pumpAndSettle();

      expect(find.textContaining('Richtig ist:'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await drain(tester);
    });

    testWidgets('a choice card plays the clip once picked', (tester) async {
      await tester.pumpWidget(
        await harness(db, ChoiceCard(props(1, clip: sampleVideo))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Haus'));
      await settle(tester);

      expect(find.byType(SignVideo), findsOneWidget);
      expect(video.opened, hasLength(1));
      await drain(tester);
    });
  });

  group('the letter drill', () {
    testWidgets('a broken request says so', (tester) async {
      stubApiFailure();
      await tester.pumpWidget(
        await harness(db, CharsetScreen(db: db, charset: Charset.alphabet)),
      );
      await settle(tester, steps: 20);

      expect(find.textContaining('nicht geladen werden'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the clip playing out moves to the next letter', (
      tester,
    ) async {
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

      expect(find.text('Buchstabe 1 von 4'), findsOneWidget);
      video.finish(video.opened.length - 1);
      await settle(tester);

      expect(find.text('Buchstabe 2 von 4'), findsOneWidget);
      await drain(tester);
    });
  });

  group('the lists screen', () {
    testWidgets('a topic pulls its words in', (tester) async {
      stubEcho();

      await tester.pumpWidget(await harness(db, ListsScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begrüßung').last);
      await settle(tester, steps: 20);

      final list = (await allLists(
        db,
      )).firstWhere((l) => l.name == 'Begrüßung');
      expect(await listEntryIds(db, list.id), isNotEmpty);
      await drain(tester);
    });

    testWidgets('a broken topic pull says so', (tester) async {
      stubApiFailure();

      await tester.pumpWidget(await harness(db, ListsScreen(db: db)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begrüßung').last);
      // Settles retry backoff before snackbar auto-dismissal timeout.
      await settle(tester, steps: 8);

      expect(
        find.textContaining('konnte nicht geladen werden'),
        findsOneWidget,
      );
      expect(find.text('Begrüßung'), findsWidgets);
      await drain(tester);
    });

    testWidgets('a picked file lands as a new list', (tester) async {
      final file = File('${tmp.path}/geteilt.dgsliste')
        ..writeAsStringSync(
          '{"schema":"signdict-liste/v1","name":"Bad",'
          '"entries":[{"id":1,"text":"Hallo"}]}',
        );
      channels.pick = file.path;
      stubApi({
        'e0': {'id': 1, 'text': 'Hallo'},
      });

      await tester.pumpWidget(await harness(db, ListsScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Geteilte Liste öffnen'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      // Subsequent actions must stay on real clock following picker handoff.
      await tester.runAsync(() async {
        await tester.tap(find.text('Übernehmen'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);

      expect((await allLists(db)).map((l) => l.name), contains('Bad'));
      await drain(tester);
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      channels.pick = null;
      await tester.pumpWidget(await harness(db, ListsScreen(db: db)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Geteilte Liste öffnen'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      await drain(tester);
    });
  });

  testWidgets('a card without a video still asks', (tester) async {
    await cacheEntries(db, [sampleEntry(id: 9, text: 'Ohne')]);
    final entry = (await getEntry(db, 9))!;

    await tester.pumpWidget(
      await harness(
        db,
        SelfRatedCard(
          CardProps(
            db: db,
            entry: entry,
            card: newCard(9, Direction.production, DateTime.now()),
            video: null,
            pool: const [],
            onAnswer: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ohne'), findsOneWidget);
    await drain(tester);
  });

  test('a rating maps to the four buttons', () {
    expect(f.Rating.values.length, greaterThanOrEqualTo(4));
  });
}
