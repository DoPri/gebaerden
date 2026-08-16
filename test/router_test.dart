import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/theme.dart';
import 'package:gebaerden/ui/router.dart';
import 'package:go_router/go_router.dart';

import 'channels.dart';
import 'fake_storage.dart';
import 'harness.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeChannels channels;
  late GoRouter router;

  setUpAll(() {
    // Without this the downloader keeps its store on its own isolate, which
    // never sees the mocked channels.
    FileDownloader(persistentStorage: MemoryStorage());
  });

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
    downloads = Downloads(db);
    router = buildRouter(db);
    // The app widget walks the index on the first start. An empty index ends
    // that walk at once. A failing one would be retried after a backoff and
    // that timer outlives the tree these tests tear down.
    stubApi({'index': <Object>[]});
  });

  tearDown(() async {
    router.dispose();
    channels.remove();
    await db.close();
  });

  Future<Widget> app() async {
    final settings = AppSettings(db);
    await settings.load();
    return NetworkScope(
      notifier: NetworkStatus(),
      child: SettingsScope(
        notifier: settings,
        child: MaterialApp.router(
          theme: appTheme(Brightness.light),
          locale: appLocale,
          supportedLocales: appLocales,
          localizationsDelegates: appDelegates,
          routerConfig: router,
        ),
      ),
    );
  }

  testWidgets('starts on the dictionary', (tester) async {
    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    expect(find.text('Wörterbuch'), findsWidgets);
    expect(find.text('NACH BUCHSTABE'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the tabs switch between the four sections', (tester) async {
    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    for (final label in ['Lernen', 'Listen', 'Mehr']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(find.text(label), findsWidgets);
    }
    await drain(tester);
  });

  testWidgets('a letter opens its own screen and comes back', (tester) async {
    stubApi({'search': <Object>[]});
    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await settle(tester);
    expect(find.byTooltip('Zurück'), findsOneWidget);

    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('NACH BUCHSTABE'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an entry route renders the entry', (tester) async {
    stubApi({
      'entry': {'id': 835, 'text': 'Beispielsatz'},
    });
    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    router.push('/eintrag/835');
    await settle(tester);

    expect(find.text('Beispielsatz'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an entry id that is not a number says so', (tester) async {
    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    router.push('/eintrag/nope');
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Diese Adresse gibt es nicht'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an address nothing matches leads back', (tester) async {
    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    router.push('/gibtesnicht');
    await settle(tester);
    expect(find.textContaining('Diese Adresse gibt es nicht'), findsOneWidget);

    await tester.tap(find.text('Zum Wörterbuch'));
    await settle(tester);
    expect(find.text('NACH BUCHSTABE'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a list route renders the list', (tester) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);

    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    router.push('/listen/${list.id}');
    await settle(tester);

    expect(find.text('Küche'), findsWidgets);
    expect(find.text('Hallo'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the drills have their own routes', (tester) async {
    stubApi({});
    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    router.push('/zahlen');
    await settle(tester);
    expect(find.text('Zahlen'), findsWidgets);
    await drain(tester);
  });

  testWidgets('learning from a list reads the query parameter', (tester) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Tschüss', currentVideo: sampleVideo),
    ]);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);

    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();

    router.go('/lernen?liste=${list.id}');
    await tester.pumpAndSettle();

    // Only the one word in the list, not both cached entries.
    expect(find.text('1'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('duplicating a list navigates to the copy', (tester) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
    ]);
    final list = await createList(db, 'Küche');
    await addToList(db, list.id, [1]);

    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();
    router.push('/listen/${list.id}');
    await settle(tester);

    await tester.tap(find.byTooltip('Liste duplizieren'));
    await settle(tester);

    final copy = (await allLists(
      db,
    )).firstWhere((l) => l.name.endsWith('(Kopie)'));
    expect(await listEntryIds(db, copy.id), [1]);
    expect(find.text('Küche (Kopie)'), findsWidgets);
    await drain(tester);
  });

  group('the app widget', () {
    testWidgets('builds with the stored theme', (tester) async {
      final settings = AppSettings(db);
      await settings.load();
      await settings.setThemeMode(ThemeMode.dark);

      final network = NetworkStatus();
      await tester.pumpWidget(
        GebaerdenApp(db: db, settings: settings, network: network),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.title, 'DGS Lernen');
      await drain(tester);
    });

    testWidgets('a theme change reaches the tree', (tester) async {
      final settings = AppSettings(db);
      await settings.load();
      final network = NetworkStatus();

      await tester.pumpWidget(
        GebaerdenApp(db: db, settings: settings, network: network),
      );
      await tester.pumpAndSettle();

      await settings.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      await drain(tester);
    });
  });
}
