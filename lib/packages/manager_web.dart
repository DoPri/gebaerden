// Offline downloads are a native-only feature.

import '../db/database.dart';
import 'spec.dart';

export 'spec.dart';

/// Nothing here downloads anything, so nothing offers it either.
const downloadsAvailable = false;

class Downloads {
  Downloads(AppDatabase db);

  Future<void> start() async {}

  Future<void> dispose() async {}

  Future<void> reconcile() async {}

  Future<void> startPackage(PackageSpec spec) async {}

  Future<void> pausePackage(String id) async {}

  Future<void> resumeById(String id) async {}

  Future<void> resumePackage(StoredPackage row) async {}

  Future<void> cancelPackage(String id) async {}

  Future<void> removeDownloads(List<int> entryIds) async {}

  Future<bool> isDownloaded(int entryId) async => false;
}

late Downloads downloads;

Future<void> refreshDownloadFor(AppDatabase db, int entryId) async {}
