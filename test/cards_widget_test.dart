import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/ui/cards.dart';
import 'package:gebaerden/ui/widgets/sign_video.dart';

import 'harness.dart';
import 'support.dart';

void main() {
  late AppDatabase db;
  late List<CachedEntry> pool;
  late f.Rating? answered;

  setUp(() async {
    db = testDb();
    answered = null;
    pool = await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Haus', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Baum', currentVideo: sampleVideo),
      sampleEntry(id: 3, text: 'Katze', currentVideo: sampleVideo),
      sampleEntry(id: 4, text: 'Hund', currentVideo: sampleVideo),
    ]);
  });

  tearDown(() => db.close());

  CardProps props({Direction direction = Direction.recognition}) => CardProps(
    db: db,
    entry: pool.first,
    card: newCard(1, direction, DateTime.now()),
    // Avoids platform channel setup.
    video: null,
    pool: pool,
    onAnswer: (rating) => answered = rating,
  );

  group('self rated', () {
    testWidgets('hides the word until you reveal it', (tester) async {
      await tester.pumpWidget(await harness(db, SelfRatedCard(props())));
      await tester.pumpAndSettle();

      expect(find.text('Haus'), findsNothing);
      expect(find.text('—'), findsOneWidget);

      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();
      expect(find.text('Haus'), findsOneWidget);
    });

    testWidgets('offers four grades with an interval each', (tester) async {
      await tester.pumpWidget(await harness(db, SelfRatedCard(props())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();

      for (final label in ['Nochmal', 'Schwer', 'Gut', 'Leicht']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('hands the tapped grade back', (tester) async {
      await tester.pumpWidget(await harness(db, SelfRatedCard(props())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gut'));

      expect(answered, f.Rating.good);
    });

    testWidgets('the other direction shows the word right away', (
      tester,
    ) async {
      await tester.pumpWidget(
        await harness(
          db,
          SelfRatedCard(props(direction: Direction.production)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Haus'), findsOneWidget);
      expect(find.text('Wie wird das gebärdet?'), findsOneWidget);
    });
  });

  group('cards with a video', () {
    CardProps withVideo({Direction direction = Direction.recognition}) =>
        CardProps(
          db: db,
          entry: pool.first,
          card: newCard(1, direction, DateTime.now()),
          video: sampleVideo,
          pool: pool,
          onAnswer: (rating) => answered = rating,
        );

    testWidgets('the sign shows before the word', (tester) async {
      await tester.pumpWidget(await harness(db, SelfRatedCard(withVideo())));
      await tester.pumpAndSettle();

      expect(find.byType(SignVideo), findsOneWidget);
      expect(find.text('Haus'), findsNothing);
      await drain(tester);
    });

    testWidgets('the other way round the sign comes after the reveal', (
      tester,
    ) async {
      await tester.pumpWidget(
        await harness(
          db,
          SelfRatedCard(withVideo(direction: Direction.production)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignVideo), findsNothing);
      await tester.tap(find.text('Auflösen'));
      await tester.pumpAndSettle();
      expect(find.byType(SignVideo), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the typing card shows the sign too', (tester) async {
      await tester.pumpWidget(await harness(db, TypingCard(withVideo())));
      await tester.pumpAndSettle();

      expect(find.byType(SignVideo), findsOneWidget);
      await drain(tester);
    });
  });

  group('multiple choice', () {
    testWidgets('shows four answers, one of them right', (tester) async {
      await tester.pumpWidget(await harness(db, ChoiceCard(props())));
      await tester.pumpAndSettle();

      expect(find.text('Haus'), findsOneWidget);
      final shown = pool.where((e) => find.text(e.word).evaluate().isNotEmpty);
      expect(shown, hasLength(4));
    });

    testWidgets('a right answer counts as good', (tester) async {
      await tester.pumpWidget(await harness(db, ChoiceCard(props())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Haus'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(answered, f.Rating.good);
    });

    testWidgets('a wrong answer counts as again', (tester) async {
      await tester.pumpWidget(await harness(db, ChoiceCard(props())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Baum'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(answered, f.Rating.again);
    });

    testWidgets('a second tap changes nothing', (tester) async {
      await tester.pumpWidget(await harness(db, ChoiceCard(props())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Baum'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Haus'));
      await tester.pump(const Duration(milliseconds: 800));

      expect(answered, f.Rating.again);
    });
  });

  group('typing', () {
    testWidgets('the right word counts as good', (tester) async {
      await tester.pumpWidget(await harness(db, TypingCard(props())));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'haus');
      await tester.tap(find.text('Prüfen'));
      await tester.pump(const Duration(milliseconds: 1000));

      expect(answered, f.Rating.good);
    });

    testWidgets('a rewritten umlaut still counts', (tester) async {
      pool = await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Bär', currentVideo: sampleVideo),
      ]);
      await tester.pumpWidget(await harness(db, TypingCard(props())));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'baer');
      await tester.tap(find.text('Prüfen'));
      await tester.pump(const Duration(milliseconds: 1000));

      expect(answered, f.Rating.good);
    });

    testWidgets('a wrong word names the right one', (tester) async {
      await tester.pumpWidget(await harness(db, TypingCard(props())));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'falsch');
      await tester.tap(find.text('Prüfen'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Richtig ist: Haus'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(answered, f.Rating.again);
    });

    testWidgets('an empty answer is wrong, not right', (tester) async {
      await tester.pumpWidget(await harness(db, TypingCard(props())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Prüfen'));
      await tester.pump(const Duration(milliseconds: 1000));

      expect(answered, f.Rating.again);
    });
  });

  group('the pool', () {
    testWidgets('a short pool still fills four answers', (tester) async {
      pool = await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Haus', currentVideo: sampleVideo),
        sampleEntry(id: 2, text: 'Baum', currentVideo: sampleVideo),
      ]);

      await tester.pumpWidget(await harness(db, ChoiceCard(props())));
      await tester.pumpAndSettle();

      expect(find.text('Haus'), findsOneWidget);
      expect(find.text('Baum'), findsOneWidget);
    });

    testWidgets('a new card redraws the answers', (tester) async {
      await tester.pumpWidget(await harness(db, ChoiceCard(props())));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        await harness(
          db,
          ChoiceCard(
            CardProps(
              db: db,
              entry: pool[1],
              card: newCard(2, Direction.recognition, DateTime.now()),
              video: null,
              pool: pool,
              onAnswer: (r) => answered = r,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baum'), findsOneWidget);
    });
  });
}
