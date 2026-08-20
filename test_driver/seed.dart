import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/reminders.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/notify.dart';
import 'package:gebaerden/search/corpus.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/srs/scheduler.dart';
import 'package:gebaerden/topics.dart';

/// What both store captures share.
///
/// The state they start from.
///
/// The number under Neu in Lernen is the size of the entry cache, and the
/// cache fills over the network while the app is already up. Walking the index
/// here and waiting for it means every frame and every second of the video
/// counts the same words. forTesting() is a real file that outlives the run,
/// so the wipe comes first and the walk really runs instead of finding the
/// marker an earlier run left behind.
Future<({StoredList topic, AppSettings settings})> seedStore() async {
  // What main() does before runApp. Without it the first reminder refresh
  // walks into an uninitialised plugin, which only shows once the notification
  // permission is granted, since the scheduler checks that first.
  await initNotifications();

  db = AppDatabase.forTesting();
  downloads = Downloads(db);

  await db.customStatement('PRAGMA foreign_keys = OFF');
  for (final table in db.allTables) {
    await db.delete(table).go();
  }
  await db.customStatement('PRAGMA foreign_keys = ON');
  await ensureSystemLists(db);

  // Also what main() does. Without it the native queue never runs and a
  // package sits at nought of two for as long as anyone watches.
  await downloads.start();

  await _fillCache();

  final topic = (await importTopic(db, topics.first))!;
  await addReminder(
    db,
    topic.id,
    const Reminder(days: {1, 2, 3, 4, 5}, hour: 19, minute: 30),
  );
  await _history(topic);

  final settings = AppSettings(db);
  await settings.load();
  await settings.set('speed', 0.25);
  await settings.set('mirror', true);
  await settings.set('mode', ReviewMode.choice.name);
  return (topic: topic, settings: settings);
}

/// iterateIndex stops at the first empty page, and one flaky page from a
/// volunteer-run API reads exactly like the end of the dictionary. A walk that
/// broke off early still sets the marker and still looks finished, and the
/// number under Neu would then be wrong on every frame. So it walks again
/// until two rounds leave the cache the same size.
Future<void> _fillCache() async {
  var previous = -1;
  for (var round = 0; round < 4; round++) {
    await syncDictionary(db);
    final cached = db.entries.id.count();
    final row = await (db.selectOnly(
      db.entries,
    )..addColumns([cached])).getSingle();
    final count = row.read(cached)!;
    if (count == previous) return;
    previous = count;
  }
  throw StateError(
    'the entry cache never settled, the index walk keeps '
    'coming back with a different size',
  );
}

/// A deck that looks used: a fortnight of answers behind it and enough due
/// today that Lernen offers to start.
Future<void> _history(StoredList topic) async {
  final ids = await listEntryIds(db, topic.id);
  final now = DateTime.now();

  for (final (i, entryId) in ids.indexed) {
    // Written, not updated. getOrCreateCard hands back a row that is not in
    // the table yet, only gradeCard puts one there, and an update against a
    // card that does not exist leaves the trainer empty and hides the
    // statistics, which count rows.
    final card = await getOrCreateCard(db, entryId, Direction.recognition);
    await db
        .into(db.cards)
        .insertOnConflictUpdate(
          card.copyWith(
            state: 2,
            stability: Value(3.0 + i),
            difficulty: const Value(5),
            // Half of them are waiting, the rest sits in the future.
            due: now.add(Duration(days: i.isEven ? -1 : 2 + i)),
            lastReview: Value(now.subtract(Duration(days: 1 + i % 5))),
            reps: 2 + i % 4,
          ),
        );

    for (var day = 0; day < 12; day++) {
      // Not every day and not the same count, so the bars differ.
      if ((i + day) % 3 == 0) continue;
      await db
          .into(db.reviews)
          .insert(
            ReviewsCompanion.insert(
              cardId: card.id,
              entryId: entryId,
              rating: 3,
              reviewedAt: now.subtract(Duration(days: day, minutes: i)),
              before: '{}',
            ),
          );
    }
  }
}

/// Waits for something that arrives over the network.
///
/// A fixed pause is a guess. The search, the drill and the trainer video all
/// come off signdict.org, and the capture that walked into an empty result
/// list failed on `Iterable.first` with nothing to say about which screen it
/// was on. This names it.
Future<void> waitFor(WidgetTester tester, String what, Finder target) async {
  for (var round = 0; round < 50; round++) {
    if (target.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }
  throw StateError('$what never arrived');
}

/// Waits until the thumbnails on screen have stopped arriving.
///
/// They are fetched one by one and a list that is still filling in looks
/// half broken on film. Counting decoded images rather than Image widgets,
/// because an Image that has not loaded yet paints a RawImage with no picture
/// in it, and some thumbnails 404 upstream and never load at all, so the
/// signal is that the count stopped growing.
Future<void> waitForThumbnails(WidgetTester tester) async {
  var previous = -1;
  for (var round = 0; round < 50; round++) {
    final loaded = find
        .byType(RawImage)
        .evaluate()
        .where((e) => (e.widget as RawImage).image != null)
        .length;
    // Not before the first one has arrived. Counting a stable zero is how the
    // filmed pass opened on a list of grey placeholders.
    if (loaded > 0 && loaded == previous) return;
    previous = loaded;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }
}

/// The tab screens are longer than the display once a deck is due, and a tap
/// on a row that is not on screen finds nothing.
Future<void> reach(WidgetTester tester, Finder target) => tester
    .scrollUntilVisible(target, 160, scrollable: find.byType(Scrollable).first);

/// Scrolls without touching the screen.
///
/// A drag would do the same, but the binding paints a crosshair wherever a
/// test pointer goes down and the film keeps whatever is on screen. Driving
/// the position directly leaves no pointer behind.
Future<void> glide(WidgetTester tester, double to, Duration span) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).hitTestable().first,
  );
  await tester.runAsync(
    () => scrollable.position.animateTo(
      to,
      duration: span,
      curve: Curves.easeInOut,
    ),
  );
}
