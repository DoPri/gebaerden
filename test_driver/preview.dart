import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Receives the timeline the tour reports and drops it next to the recording.
/// `tools/preview.py` reads it to know when each caption goes over the video.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final file = File('build/preview/timeline.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  },
);
