import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'db/database.dart';
import 'db/reminders.dart';
import 'packages/manager.dart';
import 'platform/network.dart';
import 'platform/notify.dart';
import 'search/corpus.dart';
import 'settings.dart';
import 'theme.dart';
import 'ui/lists_screen.dart';
import 'ui/router.dart';
import 'ui/tour.dart';

const appLocale = Locale('de');
const appLocales = [appLocale];
const appDelegates = <LocalizationsDelegate<Object?>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  db = AppDatabase();

  // Before the queue. start() mirrors the package rows into the shade right
  // away, and an uninitialized plugin has no small icon, which the native side
  // answers with a NullPointerException instead of a notification.
  await initNotifications();

  downloads = Downloads(db);
  await downloads.start();

  final settings = AppSettings(db);
  await settings.load();

  final network = NetworkStatus();
  await network.start();

  runApp(GebaerdenApp(db: db, settings: settings, network: network));
}

class GebaerdenApp extends StatefulWidget {
  const GebaerdenApp({
    required this.db,
    required this.settings,
    required this.network,
    super.key,
  });

  final AppDatabase db;
  final AppSettings settings;
  final NetworkStatus network;

  @override
  State<GebaerdenApp> createState() => _GebaerdenAppState();
}

class _GebaerdenAppState extends State<GebaerdenApp>
    with WidgetsBindingObserver {
  late final _router = buildRouter(widget.db);
  StreamSubscription<List<SharedMediaFile>>? _shared;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reminderTapHandler = _openReminder;
    _listenForSharedFiles();
    unawaited(_refreshReminder());
    // The trainer counts what the entry cache holds and nothing but browsing
    // used to fill it, so a fresh install opened Lernen on zero and zero.
    // Unwatched on purpose since this is metadata off the index, the app has to be
    // usable meanwhile and no network must not hold the start up.
    unawaited(syncDictionaryOnce(widget.db));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    reminderTapHandler = null;
    _shared?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The native queue keeps running while we are gone, so catch up on return.
    unawaited(downloads.reconcile());
    unawaited(_refreshReminder());
    // A first start without signal leaves the trainer without words and the
    // marker is only set once the walk got through. Coming back is the moment
    // to try again. After that it costs one read of a single row.
    unawaited(syncDictionaryOnce(widget.db));
  }

  /// The reminder text carries a due count, which is stale the next morning.
  /// Each one counts its own list.
  Future<void> _refreshReminder() async {
    await refreshReminders(
      await dueReminders(widget.db, widget.settings.directions),
    );
  }

  /// A tap on a reminder belongs in the trainer of the list that sent it.
  void _openReminder(String listId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _router.go('/lernen?liste=$listId');
    });
  }

  void _listenForSharedFiles() {
    // receive_sharing_intent has no web implementation, its channel would
    // throw. Nothing hands a file to a browser tab anyway.
    if (kIsWeb) return;
    _shared = ReceiveSharingIntent.instance.getMediaStream().listen(
      _openShared,
    );
    // The navigator has to be there before a dialog can go up.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await handleNotificationLaunch();
      await _openShared(await ReceiveSharingIntent.instance.getInitialMedia());
      await ReceiveSharingIntent.instance.reset();
    });
  }

  Future<void> _openShared(List<SharedMediaFile> files) async {
    for (final file in files) {
      final context = rootKey.currentContext;
      if (context == null || !context.mounted) return;
      await openSharedPath(context, widget.db, file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NetworkScope(
      notifier: widget.network,
      child: SettingsScope(
        notifier: widget.settings,
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) => MaterialApp.router(
            title: 'DGS Lernen',
            debugShowCheckedModeBanner: false,
            locale: appLocale,
            supportedLocales: appLocales,
            localizationsDelegates: appDelegates,
            theme: appTheme(Brightness.light, widget.settings.accent),
            darkTheme: appTheme(Brightness.dark, widget.settings.accent),
            themeMode: widget.settings.themeMode,
            // The screens in the tab shell carry no AppBar, so nothing else
            // would tell the system bars which way to draw their icons. Sits
            // inside the app, where the resolved brightness is known and
            // themeMode system is already accounted for.
            // The tour sits above the router, so its spotlight stays on top
            // of a pushed screen as well.
            builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: systemOverlay(Theme.of(context).brightness),
              child: Tour(db: widget.db, router: _router, child: child!),
            ),
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
