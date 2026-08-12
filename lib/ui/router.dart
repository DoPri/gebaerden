import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../packages/manager.dart';
import '../srs/charset.dart';
import 'charset_screen.dart';
import 'dictionary_screen.dart';
import 'entry_screen.dart';
import 'learn_screen.dart';
import 'lists_screen.dart';
import 'more_screen.dart';
import 'offline_screen.dart';
import 'shell.dart';

final rootKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(AppDatabase db) {
  return GoRouter(
    navigatorKey: rootKey,
    routes: [
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/eintrag/:id',
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
      // On the web the address bar is a way in of its own, and the screen
      // would offer packages that no queue picks up.
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
