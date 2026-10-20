import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/src/compression_worker_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

void main() {
  test('options retain every default and opt-in across the worker boundary',
      () {
    for (final original in [
      const PdfCompressionOptions(),
      const PdfCompressionOptions(
        recompressStreams: false,
        removeUnusedResources: false,
        deduplicate: false,
        subsetFonts: false,
        targetDpi: 144.5,
        jpegQuality: 17,
        deflateLevel: 2,
        allowInvalidateSignatures: true,
      ),
    ]) {
      final result =
          compressionOptionsFromJson(compressionOptionsToJson(original));
      expect(result.recompressStreams, original.recompressStreams);
      expect(result.removeUnusedResources, original.removeUnusedResources);
      expect(result.deduplicate, original.deduplicate);
      expect(result.subsetFonts, original.subsetFonts);
      expect(result.targetDpi, original.targetDpi);
      expect(result.jpegQuality, original.jpegQuality);
      expect(result.deflateLevel, original.deflateLevel);
      expect(
          result.allowInvalidateSignatures, original.allowInvalidateSignatures);
    }
  });

  test(
      'report preserves every count, step and warning without copying PDF data',
      () {
    final original = _result();
    final transferred = Uint8List.fromList(original.bytes);
    final report = compressionReportToJson(original);
    final result = compressionResultFromJson(transferred, report);

    expect(identical(result.bytes, transferred), isTrue);
    expect(result.bytes, original.bytes);
    expect(result.bytesBefore, original.bytesBefore);
    expect(result.bytesAfter, original.bytesAfter);
    expect(result.objectsBefore, original.objectsBefore);
    expect(result.objectsAfter, original.objectsAfter);
    expect(result.streamsDeflated, original.streamsDeflated);
    expect(result.compacted, original.compacted);
    expect(result.resourcesRemoved, original.resourcesRemoved);
    expect(result.duplicatesRemoved, original.duplicatesRemoved);
    expect(result.fontsSubset, original.fontsSubset);
    expect(result.imagesRecompressed, original.imagesRecompressed);
    expect(result.bytesSaved, original.bytesSaved);
    expect(result.ratio, original.ratio);
    expect(result.warnings, original.warnings);
    expect(result.steps.length, original.steps.length);
    for (var i = 0; i < result.steps.length; i++) {
      expect(result.steps[i].kind, original.steps[i].kind);
      expect(result.steps[i].bytesBefore, original.steps[i].bytesBefore);
      expect(result.steps[i].bytesAfter, original.steps[i].bytesAfter);
      expect(result.steps[i].bytesSaved, original.steps[i].bytesSaved);
    }
    expect(jsonDecode(report), isNot(contains('bytes')));
  });

  test('report also accepts a no-savings result with no steps or warnings', () {
    final bytes = Uint8List.fromList([1, 2]);
    final original = PdfCompressionResult(
      bytes: bytes,
      bytesBefore: bytes.length,
      bytesAfter: bytes.length,
      objectsBefore: 1,
      objectsAfter: 1,
      streamsDeflated: 0,
      compacted: false,
    );
    final result = compressionResultFromJson(
      bytes,
      compressionReportToJson(original),
    );
    expect(result.compacted, isFalse);
    expect(result.bytesSaved, 0);
    expect(result.steps, isEmpty);
    expect(result.warnings, isEmpty);
    expect(result.resourcesRemoved, 0);
    expect(result.duplicatesRemoved, 0);
    expect(result.fontsSubset, 0);
    expect(result.imagesRecompressed, 0);
  });

  test('malformed or mismatched option envelopes fail clearly', () {
    final encoded = compressionOptionsToJson(const PdfCompressionOptions());
    for (final json in [
      '[]',
      '{',
      _replace(encoded, 'version', 100),
      _replace(encoded, 'recompressStreams', null),
      _replace(encoded, 'targetDpi', '150'),
      _replace(encoded, 'jpegQuality', 70.5),
    ]) {
      expect(() => compressionOptionsFromJson(json), throwsFormatException);
    }
  });

  test('report rejects damaged transfers and invalid metadata', () {
    final original = _result();
    final encoded = compressionReportToJson(original);
    expect(
      () => compressionResultFromJson(Uint8List(1), encoded),
      throwsFormatException,
    );
    for (final json in [
      _replace(encoded, 'version', 100),
      _replace(encoded, 'objectsBefore', '12'),
      _replace(encoded, 'warnings', ['Preserved image', 7]),
      _replace(encoded, 'steps', [null]),
      _replace(encoded, 'steps', [
        {'kind': 'unexpected', 'bytesBefore': 5, 'bytesAfter': 3},
      ]),
    ]) {
      expect(
        () => compressionResultFromJson(original.bytes, json),
        throwsFormatException,
      );
    }
  });
}

PdfCompressionResult _result() => PdfCompressionResult(
      bytes: Uint8List.fromList([1, 2, 3]),
      bytesBefore: 103,
      bytesAfter: 3,
      objectsBefore: 99,
      objectsAfter: 61,
      streamsDeflated: 17,
      compacted: true,
      resourcesRemoved: 7,
      duplicatesRemoved: 13,
      fontsSubset: 5,
      imagesRecompressed: 3,
      steps: [
        for (final kind in PdfCompressionKind.values)
          PdfCompressionStep(
            kind: kind,
            bytesBefore: 103 - kind.index * 20,
            bytesAfter: 83 - kind.index * 20,
          ),
      ],
      warnings: [
        'Unsupported image preserved.',
        'Embedded font “太陽” preserved.'
      ],
    );

String _replace(String json, String key, Object? value) {
  final values = jsonDecode(json) as Map<String, dynamic>;
  values[key] = value;
  return jsonEncode(values);
}
