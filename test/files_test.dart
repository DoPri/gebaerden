import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/platform/files.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('files_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a file the picker read into memory keeps its umlauts', () async {
    // This is what Android hands over and readAsString would mangle it.
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode('Begrüßung')),
      name: 'liste.dgsliste',
    );
    expect(await readText(file), 'Begrüßung');
  });

  test('a file on disk keeps its umlauts', () async {
    final path = '${tmp.path}/liste.dgsliste';
    File(path).writeAsStringSync('Begrüßung');
    expect(await readText(XFile(path)), 'Begrüßung');
  });

  test('a file that is not UTF-8 still turns into text', () async {
    // The picker does not enforce the extension, so anything can arrive.
    // The parsers downstream fail with a friendly message on this.
    final file = XFile.fromData(
      Uint8List.fromList([0xFF, 0xFE, 0x61]),
      name: 'liste.dgsliste',
    );
    expect(await readText(file), hasLength(3));
  });
}
