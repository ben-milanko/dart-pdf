import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

/// Metadata travels as JSON while the PDF storage is transferred separately.
/// Keep a version on each envelope so mismatched cached workers fail clearly.
const compressionWorkerProtocolVersion = 1;

String compressionOptionsToJson(PdfCompressionOptions options) => jsonEncode({
      'version': compressionWorkerProtocolVersion,
      'recompressStreams': options.recompressStreams,
      'removeUnusedResources': options.removeUnusedResources,
      'deduplicate': options.deduplicate,
      'subsetFonts': options.subsetFonts,
      'targetDpi': options.targetDpi,
      'jpegQuality': options.jpegQuality,
      'deflateLevel': options.deflateLevel,
      'allowInvalidateSignatures': options.allowInvalidateSignatures,
    });

PdfCompressionOptions compressionOptionsFromJson(String json) {
  final values = _envelope(json);
  final dpi = values['targetDpi'];
  if (dpi != null && dpi is! num) {
    throw const FormatException('Invalid compression targetDpi.');
  }
  return PdfCompressionOptions(
    recompressStreams: _field<bool>(values, 'recompressStreams'),
    removeUnusedResources: _field<bool>(values, 'removeUnusedResources'),
    deduplicate: _field<bool>(values, 'deduplicate'),
    subsetFonts: _field<bool>(values, 'subsetFonts'),
    targetDpi: (dpi as num?)?.toDouble(),
    jpegQuality: _field<int>(values, 'jpegQuality'),
    deflateLevel: _field<int>(values, 'deflateLevel'),
    allowInvalidateSignatures:
        _field<bool>(values, 'allowInvalidateSignatures'),
  );
}

String compressionReportToJson(PdfCompressionResult result) => jsonEncode({
      'version': compressionWorkerProtocolVersion,
      'bytesBefore': result.bytesBefore,
      'bytesAfter': result.bytesAfter,
      'objectsBefore': result.objectsBefore,
      'objectsAfter': result.objectsAfter,
      'streamsDeflated': result.streamsDeflated,
      'compacted': result.compacted,
      'resourcesRemoved': result.resourcesRemoved,
      'duplicatesRemoved': result.duplicatesRemoved,
      'fontsSubset': result.fontsSubset,
      'imagesRecompressed': result.imagesRecompressed,
      'steps': [
        for (final step in result.steps)
          {
            'kind': step.kind.name,
            'bytesBefore': step.bytesBefore,
            'bytesAfter': step.bytesAfter,
          },
      ],
      'warnings': result.warnings,
    });

PdfCompressionResult compressionResultFromJson(Uint8List bytes, String json) {
  final values = _envelope(json);
  final bytesAfter = _field<int>(values, 'bytesAfter');
  if (bytesAfter != bytes.length) {
    throw const FormatException('Compression result length does not match.');
  }
  final steps = <PdfCompressionStep>[];
  for (final value in _field<List<dynamic>>(values, 'steps')) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid compression step.');
    }
    final name = _field<String>(value, 'kind');
    final matching =
        PdfCompressionKind.values.where((kind) => kind.name == name);
    if (matching.isEmpty) {
      throw FormatException('Unknown compression step: $name.');
    }
    steps.add(PdfCompressionStep(
      kind: matching.single,
      bytesBefore: _field<int>(value, 'bytesBefore'),
      bytesAfter: _field<int>(value, 'bytesAfter'),
    ));
  }
  final warnings = _field<List<dynamic>>(values, 'warnings');
  if (warnings.any((value) => value is! String)) {
    throw const FormatException('Invalid compression warnings.');
  }
  return PdfCompressionResult(
    bytes: bytes,
    bytesBefore: _field<int>(values, 'bytesBefore'),
    bytesAfter: bytesAfter,
    objectsBefore: _field<int>(values, 'objectsBefore'),
    objectsAfter: _field<int>(values, 'objectsAfter'),
    streamsDeflated: _field<int>(values, 'streamsDeflated'),
    compacted: _field<bool>(values, 'compacted'),
    resourcesRemoved: _field<int>(values, 'resourcesRemoved'),
    duplicatesRemoved: _field<int>(values, 'duplicatesRemoved'),
    fontsSubset: _field<int>(values, 'fontsSubset'),
    imagesRecompressed: _field<int>(values, 'imagesRecompressed'),
    steps: steps,
    warnings: warnings.cast<String>(),
  );
}

Map<String, dynamic> _envelope(String json) {
  final values = jsonDecode(json);
  if (values is! Map<String, dynamic> ||
      values['version'] != compressionWorkerProtocolVersion) {
    throw const FormatException('Unsupported compression worker protocol.');
  }
  return values;
}

T _field<T>(Map<String, dynamic> values, String name) {
  final value = values[name];
  if (value is! T) throw FormatException('Invalid compression $name.');
  return value;
}
