import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

// Offline downloads are a native-only feature.
bool localExists(String path) => false;

/// Empty bytes, which sends every caller into its errorBuilder. Unreachable
/// as long as [localExists] stays false.
ImageProvider localImage(String path) => MemoryImage(Uint8List(0));

VideoPlayerController localVideo(String path) =>
    throw UnsupportedError('no local videos in the browser');

/// The browser has no cache directory, the bytes go to the share sheet or the
/// download as they are.
Future<XFile> textFile(String name, String text) async =>
    XFile.fromData(utf8.encode(text), name: name, mimeType: 'application/json');
