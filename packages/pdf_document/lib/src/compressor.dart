import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'compressor_fonts.dart';
import 'compressor_images.dart';
import 'compressor_resources.dart';
import 'document.dart';
import 'signature.dart';

/// Independent optimisation passes. Image recompression is opt-in.
class PdfCompressionOptions {
  const PdfCompressionOptions({
    this.recompressStreams = true,
    this.removeUnusedResources = true,
    this.deduplicate = true,
    this.subsetFonts = true,
    this.targetDpi,
    this.jpegQuality = 85,
    this.deflateLevel = 9,
    this.allowInvalidateSignatures = false,
  });

  final bool recompressStreams;
  final bool removeUnusedResources;
  final bool deduplicate;
  final bool subsetFonts;

  /// Null preserves image samples. Otherwise reduces eligible colour/gray
  /// images to this resolution at their largest placement in the document.
  /// Masks, bitonal images and unsupported colour spaces are preserved.
  final double? targetDpi;
  final int jpegQuality;
  final int deflateLevel;

  /// A full rewrite invalidates existing signatures. Hosts must obtain an
  /// explicit choice before enabling this for a signed document.
  final bool allowInvalidateSignatures;
}

enum PdfCompressionPreset {
  lossless,
  screen,
  ebook,
  printer;

  String get label => switch (this) {
        lossless => 'Lossless',
        screen => 'Screen',
        ebook => 'eBook',
        printer => 'Print',
      };

  PdfCompressionOptions get options => switch (this) {
        lossless => const PdfCompressionOptions(),
        screen => const PdfCompressionOptions(targetDpi: 72, jpegQuality: 60),
        ebook => const PdfCompressionOptions(targetDpi: 150, jpegQuality: 75),
        printer => const PdfCompressionOptions(targetDpi: 300, jpegQuality: 90),
      };
}

enum PdfCompressionKind { structure, resources, fonts, images, duplicates }

/// Exact sequential file-size accounting, including writer overhead.
class PdfCompressionStep {
  const PdfCompressionStep({
    required this.kind,
    required this.bytesBefore,
    required this.bytesAfter,
  });

  final PdfCompressionKind kind;
  final int bytesBefore;
  final int bytesAfter;
  int get bytesSaved => bytesBefore - bytesAfter;
  String get label => switch (kind) {
        PdfCompressionKind.structure => 'Document structure and streams',
        PdfCompressionKind.resources => 'Unused resources',
        PdfCompressionKind.fonts => 'Font subsetting',
        PdfCompressionKind.images => 'Image optimisation',
        PdfCompressionKind.duplicates => 'Duplicate resources',
      };
}

/// The smaller of the original and optimised file, with a savings report.
class PdfCompressionResult {
  const PdfCompressionResult({
    required this.bytes,
    required this.bytesBefore,
    required this.bytesAfter,
    required this.objectsBefore,
    required this.objectsAfter,
    required this.streamsDeflated,
    required this.compacted,
    this.resourcesRemoved = 0,
    this.duplicatesRemoved = 0,
    this.fontsSubset = 0,
    this.imagesRecompressed = 0,
    this.steps = const [],
    this.warnings = const [],
  });

  final Uint8List bytes;
  final int bytesBefore;
  final int bytesAfter;
  final int objectsBefore;
  final int objectsAfter;
  final int streamsDeflated;
  final bool compacted;
  final int resourcesRemoved;
  final int duplicatesRemoved;
  final int fontsSubset;
  final int imagesRecompressed;

  /// Empty when no smaller file was found. Otherwise these savings sum to
  /// [bytesSaved]. Structural framing can cost bytes on very small inputs.
  final List<PdfCompressionStep> steps;

  /// Explains unsupported content that was preserved unchanged.
  final List<String> warnings;
  int get bytesSaved => bytesBefore - bytesAfter;
  double get ratio => bytesBefore == 0 ? 0 : bytesSaved / bytesBefore;
  double get savingsFraction => ratio;
}

/// Produces a standalone optimised copy without mutating the source graph.
///
/// The default passes preserve appearance. Lossy image processing is enabled
/// only with [PdfCompressionOptions.targetDpi]. The rewrite drops unreachable
/// objects and incremental history, uses PDF 1.7 object/xref streams and never
/// returns a larger file. Encryption and partial source buffers are refused.
///
/// This synchronous, pure-Dart API also runs on the web. Native Flutter hosts
/// should dispatch it through `compute` or an isolate for large documents;
/// web hosts may run the same entry point in a worker.
class PdfCompressor {
  PdfCompressor._();

  /// Optimises the committed bytes in [document]. Use `PdfEditor.compress`
  /// to include pending editor mutations.
  static PdfCompressionResult optimize(
    PdfDocument document, {
    PdfCompressionOptions options = const PdfCompressionOptions(),
  }) {
    RangeError.checkValueInInterval(options.deflateLevel, 0, 9, 'deflateLevel');
    RangeError.checkValueInInterval(options.jpegQuality, 1, 100, 'jpegQuality');
    final dpi = options.targetDpi;
    if (dpi != null && (!dpi.isFinite || dpi <= 0 || dpi > 2400)) {
      throw ArgumentError.value(dpi, 'targetDpi', 'must be in (0, 2400]');
    }
    if (document.cos.isEncrypted) {
      throw ArgumentError('Cannot optimise an encrypted document. '
          'Decrypt a copy first.');
    }
    if (document.cos.populatedRanges != null) {
      throw ArgumentError('Load the complete document before optimising it.');
    }
    final original = document.cos.bytes;
    var working = PdfDocument.open(original);
    final signed = PdfSignature.of(working).isNotEmpty;
    if (signed && !options.allowInvalidateSignatures) {
      throw ArgumentError('Optimisation invalidates digital signatures. '
          'Set allowInvalidateSignatures to explicitly allow a rewritten copy.');
    }
    final warnings = <String>[
      if (signed) 'Digital signatures are invalidated in the rewritten copy.',
    ];
    final pageCount = working.pageCount;
    final steps = <PdfCompressionStep>[];
    final initial = CosCompactor(working.cos,
            deflateLevel: options.deflateLevel,
            recompressStreams: options.recompressStreams)
        .run();
    var current = initial.bytes;
    var objectsAfter = initial.objectsAfter;
    working = PdfDocument.open(current);
    steps.add(PdfCompressionStep(
      kind: PdfCompressionKind.structure,
      bytesBefore: original.length,
      bytesAfter: current.length,
    ));

    // Each pass is measured against the last accepted result. Reopening also
    // clears derived caches and ensures all subsequent edits see live refs.
    bool finishPass(PdfCompressionKind kind, {required bool changed}) {
      if (!changed) {
        steps.add(PdfCompressionStep(
            kind: kind,
            bytesBefore: current.length,
            bytesAfter: current.length));
        return false;
      }
      final rewritten = CosCompactor(working.cos,
              deflateLevel: options.deflateLevel, recompressStreams: false)
          .run();
      final accepted = rewritten.bytes.length < current.length;
      steps.add(PdfCompressionStep(
        kind: kind,
        bytesBefore: current.length,
        bytesAfter: accepted ? rewritten.bytes.length : current.length,
      ));
      if (accepted) {
        current = rewritten.bytes;
        objectsAfter = rewritten.objectsAfter;
      }
      working = PdfDocument.open(current);
      return accepted;
    }

    var resources = 0;
    var fonts = 0;
    var images = 0;
    var duplicates = 0;
    if (options.removeUnusedResources) {
      final result = prunePdfResources(working);
      warnings.addAll(result.warnings);
      if (finishPass(PdfCompressionKind.resources,
          changed: result.resourcesRemoved > 0)) {
        resources = result.resourcesRemoved;
      }
    }
    if (options.subsetFonts) {
      final result = subsetPdfFonts(working);
      warnings.addAll(result.warnings);
      if (finishPass(PdfCompressionKind.fonts,
          changed: result.fontsSubset > 0)) {
        fonts = result.fontsSubset;
      }
    }
    if (dpi != null) {
      final result = optimizePdfImages(working,
          targetDpi: dpi, jpegQuality: options.jpegQuality);
      warnings.addAll(result.warnings);
      if (finishPass(PdfCompressionKind.images,
          changed: result.imagesRecompressed > 0)) {
        images = result.imagesRecompressed;
      }
    }
    if (options.deduplicate) {
      final count = deduplicatePdfResources(working);
      if (finishPass(PdfCompressionKind.duplicates, changed: count > 0)) {
        duplicates = count;
      }
    }
    // Parse every page's geometry and content linkage before offering output.
    if (working.pageCount != pageCount) {
      throw StateError('Optimisation changed the page count.');
    }
    for (var i = 0; i < pageCount; i++) {
      final page = working.page(i);
      page.mediaBox;
      page.resources;
      page.annotations;
    }
    final smaller = current.length < original.length;
    return PdfCompressionResult(
      bytes: smaller ? current : Uint8List.fromList(original),
      bytesBefore: original.length,
      bytesAfter: smaller ? current.length : original.length,
      objectsBefore: initial.objectsBefore,
      objectsAfter: smaller ? objectsAfter : initial.objectsBefore,
      streamsDeflated: smaller ? initial.streamsDeflated : 0,
      compacted: smaller,
      resourcesRemoved: smaller ? resources : 0,
      fontsSubset: smaller ? fonts : 0,
      imagesRecompressed: smaller ? images : 0,
      duplicatesRemoved: smaller ? duplicates : 0,
      steps: smaller ? List.unmodifiable(steps) : const [],
      warnings: List.unmodifiable(warnings.toSet()),
    );
  }
}
