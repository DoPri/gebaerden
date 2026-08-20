import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/db/lists.dart';
import 'package:gebaerden/db/recent.dart';
import 'package:gebaerden/db/repo.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/theme.dart';
import 'package:gebaerden/ui/dictionary_screen.dart';
import 'package:gebaerden/ui/offline_screen.dart';
import 'package:gebaerden/ui/router.dart';
import 'package:gebaerden/ui/widgets/entry_list.dart';
import 'package:go_router/go_router.dart';
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
  late GoRouter router;

  setUpAll(() {
    // Required before accessing FileDownloader singleton.
    FileDownloader(persistentStorage: MemoryStorage());
  });

  setUp(() {
    db = testDb();
    channels = FakeChannels()..install();
    FakeVideoPlayer().install();
    downloads = Downloads(db);
    router = buildRouter(db);
  });

  tearDown(() async {
    useClient(http.Client());
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

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(await app());
    await tester.pumpAndSettle();
  }

  Future<StoredList> seededList([String name = 'Küche']) async {
    await cacheEntries(db, [
      sampleEntry(id: 1, text: 'Hallo', currentVideo: sampleVideo),
      sampleEntry(id: 2, text: 'Tschüss', currentVideo: sampleVideo),
    ]);
    final list = await createList(db, name);
    await addToList(db, list.id, [1, 2]);
    return list;
  }

  group('from the dictionary', () {
    testWidgets('a hit opens the entry', (tester) async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Haus', 'currentVideo': sampleVideo.toJson()},
        ],
        'entry': {'id': 1, 'text': 'Haus'},
      });
      await boot(tester);

      await tester.enterText(find.byType(TextField), 'Haus');
      await settle(tester);
      await tester.tap(find.widgetWithText(EntryRow, 'Haus'));
      await settle(tester);

      expect(find.byTooltip('Gebärde teilen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the newest button opens the newest entries', (tester) async {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            const StoredSetting(key: 'index:lastPage', value: 1),
          );
      stubApi({'index': <Object>[]});
      await boot(tester);

      await tester.tap(find.text('Neu'));
      await settle(tester, steps: 20);

      expect(find.byType(NewestScreen), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a random sign opens straight away', (tester) async {
      stubApi({
        'index': [
          {'id': 5, 'text': 'Zufall', 'currentVideo': sampleVideo.toJson()},
        ],
        'entry': {'id': 5, 'text': 'Zufall'},
      });
      await boot(tester);

      await tester.tap(find.text('Zufällig'));
      await settle(tester, steps: 20);

      expect(find.byTooltip('Gebärde teilen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a word from the history opens again', (tester) async {
      await cacheEntries(db, [
        sampleEntry(id: 7, text: 'Haus', currentVideo: sampleVideo),
      ]);
      await remember(db, RecentKind.entry, '7', 'Haus');
      stubApi({
        'entry': {'id': 7, 'text': 'Haus'},
      });
      await boot(tester);

      await tester.tap(find.text('Haus'));
      await settle(tester);

      expect(find.byTooltip('Gebärde teilen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('clearing the field brings the letters back', (tester) async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Haus', 'currentVideo': sampleVideo.toJson()},
        ],
      });
      await boot(tester);

      await tester.enterText(find.byType(TextField), 'Haus');
      await settle(tester);
      expect(find.text('NACH BUCHSTABE'), findsNothing);

      await tester.tap(find.byTooltip('Eingabe löschen'));
      await settle(tester);

      expect(find.text('NACH BUCHSTABE'), findsOneWidget);
      await drain(tester);
    });
  });

  group('from a list', () {
    testWidgets('the row opens the list', (tester) async {
      final list = await seededList();
      await boot(tester);

      await tester.tap(find.text('Listen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(list.name));
      await settle(tester);

      expect(find.byTooltip('Liste löschen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a word opens the entry', (tester) async {
      final list = await seededList();
      stubApi({
        'entry': {'id': 1, 'text': 'Hallo'},
      });
      await boot(tester);
      router.push('/listen/${list.id}');
      await settle(tester);

      await tester.tap(find.widgetWithText(EntryRow, 'Hallo'));
      await settle(tester);

      expect(find.byTooltip('Gebärde teilen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the button starts a session on it', (tester) async {
      final list = await seededList();
      await boot(tester);
      router.push('/listen/${list.id}');
      await settle(tester);

      await tester.tap(find.text('Diese Liste lernen'));
      await settle(tester);

      // Scroll required because lobby scope header pushes button below fold.
      await tester.scrollUntilVisible(
        find.text('Loslegen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Loslegen'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('deleting takes you back', (tester) async {
      final list = await seededList();
      await boot(tester);
      router.push('/listen/${list.id}');
      await settle(tester);

      await tester.tap(find.byTooltip('Liste löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await settle(tester);

      expect((await allLists(db)).any((l) => l.id == list.id), isFalse);
      expect(find.byTooltip('Liste löschen'), findsNothing);
      await drain(tester);
    });

    testWidgets('the rename dialog takes the enter key', (tester) async {
      final list = await seededList();
      await boot(tester);
      router.push('/listen/${list.id}');
      await settle(tester);

      await tester.tap(find.byTooltip('Liste umbenennen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bad');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(
        (await allLists(db)).firstWhere((l) => l.id == list.id).name,
        'Bad',
      );
      await drain(tester);
    });

    testWidgets('a new list is created with the enter key', (tester) async {
      await boot(tester);
      await tester.tap(find.text('Listen').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Neue Liste'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Werkzeug');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect((await allLists(db)).map((l) => l.name), contains('Werkzeug'));
      await drain(tester);
    });
  });

  group('from a letter', () {
    testWidgets('a hit opens the entry', (tester) async {
      stubApi({
        'search': [
          {'id': 1, 'text': 'Baum', 'currentVideo': sampleVideo.toJson()},
        ],
        'entry': {'id': 1, 'text': 'Baum'},
      });
      await boot(tester);

      await tester.tap(find.text('B'));
      await settle(tester);
      await tester.tap(find.widgetWithText(EntryRow, 'Baum'));
      await settle(tester);

      expect(find.byTooltip('Gebärde teilen'), findsOneWidget);
      await drain(tester);
    });
  });

  group('from the newest entries', () {
    testWidgets('a row opens the entry', (tester) async {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            const StoredSetting(key: 'index:lastPage', value: 1),
          );
      stubPer((body) {
        final page = RegExp(r'"page":(\d+)').firstMatch(body)?.group(1);
        if (page != null) {
          return {
            'index': page == '1'
                ? [
                    {
                      'id': 3,
                      'text': 'Frisch',
                      'currentVideo': sampleVideo.toJson(),
                    },
                  ]
                : <Object>[],
          };
        }
        return {
          'entry': {'id': 3, 'text': 'Frisch'},
        };
      });
      await boot(tester);

      await tester.tap(find.text('Neu'));
      await settle(tester, steps: 20);
      await tester.tap(find.widgetWithText(EntryRow, 'Frisch'));
      await settle(tester);

      expect(find.byTooltip('Gebärde teilen'), findsOneWidget);
      await drain(tester);
    });
  });

  group('from an entry', () {
    testWidgets('a related word opens next', (tester) async {
      await cacheEntries(db, [
        sampleEntry(id: 1, text: 'Haus', currentVideo: sampleVideo),
        sampleEntry(id: 2, text: 'Hausboot', currentVideo: sampleVideo),
      ]);
      stubApi({
        'entry': {'id': 1, 'text': 'Haus'},
        'search': [
          {'id': 2, 'text': 'Hausboot', 'currentVideo': sampleVideo.toJson()},
        ],
      });
      await boot(tester);
      router.push('/eintrag/1');
      await settle(tester, steps: 20);

      await tester.scrollUntilVisible(
        find.text('Hausboot'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Hausboot'));
      await settle(tester);

      expect(find.byTooltip('Gebärde teilen'), findsWidgets);
      await drain(tester);
    });
  });

  group('from the more tab', () {
    testWidgets('the offline row leads onwards', (tester) async {
      await boot(tester);
      await tester.tap(find.text('Mehr').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gebärden herunterladen'));
      await settle(tester);

      expect(find.byType(OfflineScreen), findsOneWidget);
      await drain(tester);
    });
  });

  group('from the learn tab', () {
    testWidgets('the drills have their own screens', (tester) async {
      stubApi({'search': <Object>[]});
      await boot(tester);
      await tester.tap(find.text('Lernen').last);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Fingeralphabet'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Fingeralphabet'));
      await settle(tester);

      expect(find.text('Fingeralphabet'), findsWidgets);
      await drain(tester);
    });
  });
}
