@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/src/filters/zlib_inflate_web.dart' as web;
import 'package:test/test.dart';

/// The web inflater against native zlib over the Flate streams (up to 64 KB
/// encoded) of the checked-in pdf.js and Ghent suites: wherever native zlib
/// decodes a stream, the web path must produce the same bytes, strict or not.
void main() {
  test('web inflateZlib matches native zlib across the test corpora', () {
    final files = [
      for (final suite in ['pdfjs', 'ghent'])
        ...Directory('../../test_corpora/$suite').listSync(recursive: true),
    ]
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    var streams = 0;
    var trailing = 0;
    for (final file in files) {
      final CosDocument cos;
      try {
        cos = CosDocument.open(file.readAsBytesSync());
      } on Object {
        continue;
      }
      for (final input in _flateInputs(cos)) {
        // The big image planes only cost time: the tail handling does not
        // depend on size, and the kernel is covered by the smaller streams.
        if (input.length > 64 * 1024) continue;
        final Uint8List native;
        try {
          native = inflateZlib(input);
        } on Object {
          continue; // damaged beyond native zlib; the web may recover more
        }
        streams++;
        final name = file.uri.pathSegments.last;
        expect(web.inflateZlib(input), native, reason: name);
        expect(web.inflateZlib(input, strict: true), native, reason: name);
        if (native.isNotEmpty && _archiveWebLoses(input)) trailing++;
      }
    }
    expect(streams, greaterThan(1000));
    // Streams archive's own web decoder loses to bytes after the Adler-32
    // (rotation.pdf, devicen.pdf, GWG090, ...), all of which matched native
    // above.
    expect(trailing, greaterThanOrEqualTo(23));
  });
}

bool _archiveWebLoses(Uint8List input) {
  try {
    return const ZLibDecoderWeb().decodeBytes(input).isEmpty;
  } on Object {
    return true;
  }
}

/// Each Flate stage input (after decryption and any filters before it).
Iterable<Uint8List> _flateInputs(CosDocument cos) sync* {
  final numbers = cos.objectNumbers.toList()..sort();
  for (final number in numbers) {
    final CosObject object;
    try {
      object = cos.getObject(number, 0);
    } on Object {
      continue;
    }
    if (object is! CosStream) continue;
    CosObject filter;
    try {
      filter = cos.resolve(object.dictionary['Filter']);
      if (filter is CosArray && filter.items.isNotEmpty) {
        filter = cos.resolve(filter.items.first);
      }
    } on Object {
      continue;
    }
    if (filter is! CosName ||
        (filter.value != 'FlateDecode' && filter.value != 'Fl')) {
      continue;
    }
    try {
      yield cos.decodeStreamData(object, stopBeforeFilter: filter.value);
    } on Object {
      continue;
    }
  }
}
