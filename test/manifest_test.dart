import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Verifies required Android manifest entries for plugins not validated at build time.
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
    // Required on Android API 34+ to run foreground data sync services beyond 9 minutes.
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
