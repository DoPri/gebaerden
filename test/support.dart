import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:gebaerden/db/database.dart';

AppDatabase testDb() {
  // Two in-memory databases at once is the point in the transfer tests.
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

/// A transparent pixel, so a widget test can show an image without the net.
final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
