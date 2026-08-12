import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The plugins need entries in the app manifest that nothing else checks. A
/// missing receiver costs nothing at build time and swallows every reminder.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('the reminder has its receivers', () {
    expect(
      manifest,
      contains('flutterlocalnotifications.ScheduledNotificationReceiver'),
    );
    expect(
      manifest,
      contains('flutterlocalnotifications.ScheduledNotificationBootReceiver'),
    );
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
  });

  test('a shared list finds its way in', () {
    expect(manifest, contains(r'.*\\.dgsliste'));
    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android.intent.action.VIEW'));
  });

  test('the downloads may reach the net', () {
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('the downloader may hold a foreground service', () {
    // Without these the queue stops nine minutes after the app goes away and
    // from API 34 the service does not even start.
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'),
    );
    expect(
      manifest,
      contains('androidx.work.impl.foreground.SystemForegroundService'),
    );
    expect(manifest, contains('android:foregroundServiceType="dataSync"'));
  });
}
