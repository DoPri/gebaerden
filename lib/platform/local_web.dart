import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

// Offline downloads are native-only.
bool localExists(String path) => false;

ImageProvider localImage(String path) => MemoryImage(Uint8List(0));

VideoPlayerController localVideo(String path) =>
    throw UnsupportedError('no local videos in the browser');

// Web lacks a cache directory; passes in-memory bytes directly.
Future<XFile> textFile(String name, String text) async =>
    XFile.fromData(utf8.encode(text), name: name, mimeType: 'application/json');
