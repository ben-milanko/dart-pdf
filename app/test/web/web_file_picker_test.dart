@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_pdf_editor_app/web_file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

web.File _file(String name, List<int> bytes, {String type = ''}) => web.File(
      [Uint8List.fromList(bytes).toJS].toJS,
      name,
      web.FilePropertyBag(type: type),
    );

void main() {
  test('a picked file reports its metadata and reads its bytes on demand',
      () async {
    final file = PickedWebFile(_file('cloud.pdf', [1, 2, 3, 4, 5]),
        fallbackMimeType: 'application/pdf');

    expect(file.name, 'cloud.pdf');
    expect(file.mimeType, 'application/pdf');
    expect(await file.length(), 5);
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(await file.openRead(1, 3).single, [2, 3]);
  });

  test('a browser-declared type wins over the fallback', () {
    final file = PickedWebFile(_file('k.pem', [0], type: 'text/plain'),
        fallbackMimeType: 'application/x-pem-file');
    expect(file.mimeType, 'text/plain');
  });

  test('the picker completes on selection without reading the files', () async {
    final picked = pickPdfFilesWeb();
    final input =
        web.document.querySelector('input[type=file]') as web.HTMLInputElement;
    final transfer = web.DataTransfer();
    transfer.items.add(_file('a.pdf', [7]));
    transfer.items.add(_file('b.pdf', [8, 9]));
    input.files = transfer.files;
    input.dispatchEvent(web.Event('change'));

    final files = await picked;
    expect(files.map((f) => f.name), ['a.pdf', 'b.pdf']);
    // Handed back as lazy browser-file readers, not pre-read copies.
    expect(files, everyElement(isA<PickedWebFile>()));
    expect(await files[1].readAsBytes(), [8, 9]);
    expect(web.document.querySelector('input[type=file]'), isNull);
  });
}
