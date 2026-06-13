import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/file_io.dart';

void main() {
  test('ensurePdfName adds a .pdf extension and a default stem', () {
    expect(ensurePdfName('report'), 'report.pdf');
    expect(ensurePdfName('report.pdf'), 'report.pdf');
    expect(ensurePdfName('  '), 'document.pdf');
  });

  test('saveBytesToPath overwrites the file in place', () async {
    final dir = await Directory.systemTemp.createTemp('dartpdf_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/out.pdf';

    final result = await saveBytesToPath(Uint8List.fromList([1, 2, 3, 4]), path);
    expect(result.succeeded, isTrue);
    expect(result.path, path);
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);

    // A second save overwrites, not appends.
    await saveBytesToPath(Uint8List.fromList([9, 9]), path);
    expect(await File(path).readAsBytes(), [9, 9]);
  });

  test('saveBytesToPath reports failure for an unwritable path', () async {
    final result =
        await saveBytesToPath(Uint8List(1), '/no/such/dir/out.pdf');
    expect(result.succeeded, isFalse);
    expect(result.message, startsWith('Save failed'));
  });
}
