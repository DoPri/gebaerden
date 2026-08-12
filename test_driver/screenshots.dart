import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Receives the frames the target hands over and drops them in a staging
/// folder. `tools/screenshots.py` moves them into the store metadata.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('build/screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
