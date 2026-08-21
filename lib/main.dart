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

  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  db = AppDatabase();

  // Must initialize notifications before download manager to prevent crash.
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
    // Non-blocking sync populates entry cache for fresh installs.
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
    // Sync downloads with background progress on resume.
    unawaited(downloads.reconcile());
    unawaited(_refreshReminder());
    // Retry dictionary cache sync on app resume if initial attempt failed.
    unawaited(syncDictionaryOnce(widget.db));
  }

  Future<void> _refreshReminder() async {
    await refreshReminders(
      await dueReminders(widget.db, widget.settings.directions),
    );
  }

  void _openReminder(String listId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _router.go('/lernen?liste=$listId');
    });
  }

  void _listenForSharedFiles() {
    // receive_sharing_intent lacks web support.
    if (kIsWeb) return;
    _shared = ReceiveSharingIntent.instance.getMediaStream().listen(
      _openShared,
    );
    // Wait for navigator to mount before presenting dialog.
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
            // Sets system bar icon contrast without AppBar; wraps tour above router.
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
