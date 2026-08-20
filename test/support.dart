import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:gebaerden/db/database.dart';

AppDatabase testDb() {
  // Suppresses warnings when multiple in-memory DB instances run concurrently.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

const sampleVideo = ApiVideo(
  id: 951,
  videoUrl: 'https://assets.wishlephant.com/signdict/videos/x.mp4',
  thumbnailUrl: 'https://assets.wishlephant.com/signdict/thumbnails/x.jpg',
  license: 'by-sa/3.0/de',
  copyright: 'Philipps - dgs.wikisign.org',
  updatedAt: '2017-05-07 10:52:00',
  userName: 'Wikisign DGS',
);

ApiEntry sampleEntry({
  int id = 835,
  String text = 'Zug',
  String? description,
  ApiVideo? currentVideo,
  List<ApiVideo>? videos,
}) {
  return ApiEntry(
    id: id,
    text: text,
    type: 'word',
    description: description,
    language: 'DGS',
    currentVideo: currentVideo,
    videos: videos,
  );
}

/// 1x1 transparent PNG for offline widget image rendering.
final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
