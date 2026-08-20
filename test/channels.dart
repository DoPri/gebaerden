import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mocks platform plugin method channels for tests.
class FakeChannels {
  final calls = <String>[];
  final _channels = <String>[];

  final scheduled = <Map<Object?, Object?>>[];
  final enqueued = <String>[];
  final queue = <String, String>{};

  void _queue(Map<Object?, Object?> task) {
    final id = '${task['taskId']}';
    enqueued.add(id);
    queue[id] = jsonEncode(task);
  }

  String? pick;
  bool notificationsAllowed = true;
  bool shareFails = false;
  String? shared;
  List<Map<String, Object?>> pending = [];
  String? launchPayload;
  final cancelled = <int>[];
  final shown = <Map<Object?, Object?>>[];
  List<Map<String, Object?>> active = [];
  late final Directory tempDir;

  MockStreamHandlerEventSink? _connectivity;

  void reportConnectivity(List<String> kinds) => _connectivity?.success(kinds);

  void install() {
    // Explicitly binds Android plugin implementation in test environment.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();

    _handle('flutter_timezone', (call) => 'Europe/Berlin');

    _handle('dev.fluttercommunity.plus/connectivity', (call) => ['wifi']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(
            onListen: (arguments, sink) => _connectivity = sink,
          ),
        );

    _handle('dexterous.com/flutter/local_notifications', (call) {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'areNotificationsEnabled':
        case 'requestNotificationsPermission':
        case 'requestPermissions':
          return notificationsAllowed;
        case 'pendingNotificationRequests':
          return pending;
        case 'getNotificationAppLaunchDetails':
          if (launchPayload == null) return null;
          return {
            'notificationLaunchedApp': true,
            'notificationResponse': {
              'notificationId': 1,
              'notificationResponseType': 0,
              'payload': launchPayload,
              'data': <String, Object?>{},
            },
          };
        case 'show':
          shown.add(call.arguments as Map<Object?, Object?>);
          return null;
        case 'getActiveNotifications':
          return active;
        case 'cancel':
          cancelled.add((call.arguments as Map)['id'] as int);
          return null;
        case 'zonedSchedule':
          scheduled.add(call.arguments as Map<Object?, Object?>);
          return null;
        default:
          return null;
      }
    });

    for (final name in [
      'com.bbflight.background_downloader',
      'com.bbflight.background_downloader.background',
      'com.bbflight.background_downloader.callbacks',
      'com.bbflight.background_downloader.uriutils',
    ]) {
      _handle(name, (call) {
        final args = call.arguments;
        if (call.method == 'enqueue') {
          _queue(jsonDecode((args as List<Object?>).first! as String) as Map);
          return true;
        }
        if (call.method == 'enqueueAll') {
          final tasks =
              jsonDecode((args as List<Object?>).first! as String) as List;
          for (final task in tasks) {
            _queue(task as Map);
          }
          return List.filled(tasks.length, true);
        }
        if (call.method == 'cancelTasksWithIds') {
          for (final id in args as List<Object?>) {
            queue.remove('$id');
          }
          return true;
        }
        return switch (call.method) {
          'reset' => 0,
          'allTaskIds' => queue.keys.toList(),
          'allTasks' => queue.values.toList(),
          // Background downloader expects JSON map response.
          'popResumeData' || 'popStatusUpdates' || 'popProgressUpdates' => '{}',
          'configureNotification' || 'trackTasks' || 'requireWiFi' => null,
          // 2: granted, 1: denied (downloader requires granted status).
          'permissionStatus' => notificationsAllowed ? 2 : 1,
          // Simulates unfulfilled synchronous permission request.
          'requestPermission' => false,
          _ => null,
        };
      });
    }

    _handle(
      'receive_sharing_intent/messages',
      (call) => call.method == 'getInitialMedia' ? shared : null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('receive_sharing_intent/events-media'),
          MockStreamHandler.inline(onListen: (arguments, sink) {}),
        );

    _handle('dev.fluttercommunity.plus/share', (call) {
      if (shareFails) throw PlatformException(code: 'kaputt');
      return 'success';
    });

    _handle(
      'plugins.flutter.io/file_selector',
      (call) => pick == null ? null : [pick],
    );

    // Pre-creates directory for file sharing operations.
    tempDir = Directory.systemTemp.createTempSync('gebaerden_test');
    _handle('plugins.flutter.io/path_provider', (call) => tempDir.path);
    _handle('plugins.flutter.io/url_launcher', (call) => true);
  }

  void _handle(String name, Object? Function(MethodCall) answer) {
    _channels.add(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async {
          calls.add('$name.${call.method}');
          return answer(call);
        });
  }

  void remove() {
    for (final channel in const [
      EventChannel('receive_sharing_intent/events-media'),
      EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    }
    for (final name in _channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
    _channels.clear();
  }
}
