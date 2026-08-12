import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

bool localExists(String path) => File(path).existsSync();

ImageProvider localImage(String path) => FileImage(File(path));

VideoPlayerController localVideo(String path) =>
    VideoPlayerController.file(File(path));

/// A file for the share sheet. Everything that shares text writes it to the
/// cache first, the sheet takes a path and nothing else.
Future<XFile> textFile(String name, String text) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsString(text);
  return XFile(file.path);
}
