import 'dart:convert';

import 'package:file_selector/file_selector.dart';

// XFile.readAsString defaults to latin-1 on in-memory bytes on Android.
Future<String> readText(XFile file) async =>
    utf8.decode(await file.readAsBytes(), allowMalformed: true);
