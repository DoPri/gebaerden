import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../packages/manager.dart';
import '../srs/charset.dart';
import '../theme.dart';
import 'charset_screen.dart';
import 'dictionary_screen.dart';
import 'entry_screen.dart';
import 'learn_screen.dart';
import 'lists_screen.dart';
import 'more_screen.dart';
import 'offline_screen.dart';
import 'shell.dart';
import 'widgets/pieces.dart';

final rootKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(AppDatabase db) {
  return GoRouter(
    navigatorKey: rootKey,
    // Prevents go_router from rendering unhandled route exceptions on web.
    errorBuilder: (_, _) => const _NoRoute(),
    routes: [
      GoRoute(
        parentNavigatorKey: rootKey,
        // Regex constraint prevents int.parse throwing on invalid web URLs.
        path: r'/eintrag/:id(\d+)',
        builder: (_, state) =>
            EntryScreen(db: db, id: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/buchstabe/:letter',
        builder: (_, state) =>
            LetterScreen(db: db, letter: state.pathParameters['letter']!),
      ),
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/listen/:id',
        builder: (_, state) =>
            ListScreen(db: db, id: state.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/neu',
        builder: (_, _) => NewestScreen(db: db),
      ),
      // Disable offline route on web where download queues are unsupported.
      if (downloadsAvailable)
        GoRoute(
          parentNavigatorKey: rootKey,
          path: '/offline',
          builder: (_, _) => OfflineScreen(db: db),
        ),
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/fingeralphabet',
        builder: (_, _) => CharsetScreen(db: db, charset: Charset.alphabet),
      ),
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/zahlen',
        builder: (_, _) => CharsetScreen(db: db, charset: Charset.numbers),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigation) => Shell(
          index: navigation.currentIndex,
          onSelect: (i) => navigation.goBranch(
            i,
            initialLocation: i == navigation.currentIndex,
          ),
          title: tabs[navigation.currentIndex].label,
          child: navigation,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => DictionaryScreen(db: db),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/lernen',
                builder: (_, state) => LearnScreen(
                  db: db,
                  listId: state.uri.queryParameters['liste'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/listen',
                builder: (_, _) => ListsScreen(db: db),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/mehr',
                builder: (_, _) => MoreScreen(db: db),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _NoRoute extends StatelessWidget {
  const _NoRoute();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Note('Diese Adresse gibt es nicht.', problem: true),
            // Use go() to reset tab shell state instead of pushing duplicate routes.
            AppButton(
              label: 'Zum Wörterbuch',
              icon: Icons.menu_book_outlined,
              onPressed: () => context.go('/'),
            ),
          ],
        ),
      ),
    );
  }
}
