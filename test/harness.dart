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

/// Wraps [child] with required app providers, themes, and shell scaffold.
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
        home: Scaffold(body: child),
      ),
    ),
  );
}

/// Marks onboarding tour completed to avoid overlaying app tests.
Future<void> tourSeen(AppDatabase db) => db
    .into(db.settings)
    .insertOnConflictUpdate(const StoredSetting(key: 'tourDone', value: true));

/// Mocks GraphQL responses with static data to avoid network calls.
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

/// Mocks GraphQL responses per request body for pagination tests.
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

/// Mocks word and entry lookups returning echoing test payloads.
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

/// Pumps fixed steps to advance debouncers; avoids infinite progress animation hangs.
Future<void> settle(WidgetTester tester, {int steps = 8}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Unmounts widget tree and drains timers to prevent test runner leaks.
Future<void> drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
