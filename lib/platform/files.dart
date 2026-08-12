import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// XFile.readAsString ignores the encoding and falls back to latin-1 when the
/// picker hands over bytes instead of a path, which is what Android does.
/// Malformed bytes become replacement characters, so a file that is not UTF-8
/// fails later in the parsers with their friendly message instead of here.
Future<String> readText(XFile file) async =>
    utf8.decode(await file.readAsBytes(), allowMalformed: true);
