import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the plugin channels so screens that talk to the platform can be
/// tested. Every handler records what it was asked for.
class FakeChannels {
  final calls = <String>[];
  final _channels = <String>[];

  /// What the notification plugin was told to schedule.
  final scheduled = <Map<Object?, Object?>>[];

  /// Task ids handed to the downloader.
  final enqueued = <String>[];

  /// Stands in for the native queue: task id to the task as json. Enqueueing
  /// fills it, cancelling empties it, and allTasks reads it back.
  final queue = <String, String>{};

  void _queue(Map<Object?, Object?> task) {
    final id = '${task['taskId']}';
    enqueued.add(id);
    queue[id] = jsonEncode(task);
  }

  /// What the file picker hands back.
  String? pick;

  /// Whether the device lets the app post notifications.
  bool notificationsAllowed = true;

  /// Whether handing a file to the share sheet blows up.
  bool shareFails = false;

  /// The json the sharing plugin reports on launch, null for nothing.
  String? shared;

  /// What the notification plugin reports as still queued.
  List<Map<String, Object?>> pending = [];

  /// Notification ids the app took down, in order.
  final cancelled = <int>[];

  /// What the app put into the shade, newest last.
  final shown = <Map<Object?, Object?>>[];

  /// What the system reports as still standing in the shade.
  List<Map<String, Object?>> active = [];

  /// Which directory the temp files land in.
  late final Directory tempDir;

  MockStreamHandlerEventSink? _connectivity;

  /// Reports a change the way the platform does.
  void reportConnectivity(List<String> kinds) => _connectivity?.success(kinds);

  void install() {
    // No plugin registrant runs in a test, so point the interface at the
    // Android side by hand. defaultTargetPlatform is android here.
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
          // The native queue, which is what the app asks after it was away.
          'allTaskIds' => queue.keys.toList(),
          'allTasks' => queue.values.toList(),
          // What the native side held back while the app was away, keyed by
          // task id. Nothing here, but it has to be a json map.
          'popResumeData' || 'popStatusUpdates' || 'popProgressUpdates' => '{}',
          'configureNotification' || 'trackTasks' || 'requireWiFi' => null,
          // 2 is granted, 1 denied. The downloader shows nothing when denied.
          'permissionStatus' => notificationsAllowed ? 2 : 1,
          // False stands for a request the platform did not carry out. The
          // real one answers through a callback this fake has no part in.
          'requestPermission' => false,
          _ => null,
        };
      });
    }

    // What the system handed the app on launch, as the plugin encodes it.
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

    // Null stands for the user backing out of the picker.
    _handle(
      'plugins.flutter.io/file_selector',
      (call) => pick == null ? null : [pick],
    );

    // Must exist, code writes files there before sharing them.
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
