import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:gebaerden/db/database.dart';
import 'package:gebaerden/main.dart';
import 'package:gebaerden/packages/manager.dart';
import 'package:gebaerden/platform/network.dart';
import 'package:gebaerden/settings.dart';
import 'package:gebaerden/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

/// Everything a screen expects to find above itself.
Future<Widget> harness(
  AppDatabase db,
  Widget child, {
  Brightness brightness = Brightness.light,
  bool online = true,
}) async {
  downloads = Downloads(db);

  final settings = AppSettings(db);
  await settings.load();

  final network = NetworkStatus();
  if (!online) network.goOffline();

  return NetworkScope(
    notifier: network,
    child: SettingsScope(
      notifier: settings,
      child: MaterialApp(
        theme: appTheme(brightness),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: appDelegates,
        // Screens sit inside the shell's Scaffold in the app.
        home: Scaffold(body: child),
      ),
    ),
  );
}

/// Answers every GraphQL query with the given data, so no test touches the net.
void stubApi(Map<String, dynamic> data) {
  useClient(
    MockClient(
      (_) async => http.Response(
        jsonEncode({'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
}

/// Answers each query differently, so paging can be exercised.
void stubPer(Map<String, dynamic> Function(String body) answer) {
  useClient(
    MockClient(
      (request) async => http.Response(
        jsonEncode({'data': answer(request.body)}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
}

/// Answers every exact-word lookup with the word itself and every entry
/// lookup with its id, the way the api does for letters and topic words.
void stubEcho() {
  stubPer((body) {
    final query = (jsonDecode(body) as Map<String, dynamic>)['query'] as String;
    final answer = <String, dynamic>{};

    for (final m in RegExp(
      r'(w\d+): search\(word: "([^"]*)"\)',
    ).allMatches(query)) {
      final word = m.group(2)!;
      answer[m.group(1)!] = [
        {
          'id': word.hashCode.abs() % 100000,
          'text': word,
          'currentVideo': sampleVideo.toJson(),
        },
      ];
    }
    for (final m in RegExp(r'(e\d+): entry\(id: (\d+)\)').allMatches(query)) {
      answer[m.group(1)!] = {
        'id': int.parse(m.group(2)!),
        'text': 'Wort ${m.group(2)}',
        'currentVideo': sampleVideo.toJson(),
      };
    }
    return answer;
  });
}

void stubApiFailure() {
  useClient(MockClient((_) async => http.Response('nope', 500)));
}

/// Drives the debounce and the request forward. Never pumpAndSettle here, the
/// busy indicator animates forever and would hang the test.
Future<void> settle(WidgetTester tester, {int steps = 8}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Tears the tree down and lets pending timers finish, so the binding does not
/// complain about them at the end of a test.
Future<void> drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
