import 'package:flutter/foundation.dart';

/// One downloadable file that makes up an on-device OCR model — typically an
/// ONNX network or a character dictionary.
@immutable
class PdfOcrModelFile {
  const PdfOcrModelFile({
    required this.name,
    required this.url,
    this.sha256,
    this.sizeBytes,
  });

  /// The file's cache name (also its on-disk name under the model directory).
  final String name;

  /// Where the file is downloaded from.
  final Uri url;

  /// Optional lowercase hex SHA-256 of the file. When set, a download whose
  /// digest does not match is rejected (and the partial file deleted). When
  /// null, integrity is not checked — fine for a self-hosted bundle you
  /// control, but set it for anything you ship to users.
  final String? sha256;

  /// Optional expected size in bytes, used only to weight download progress
  /// before the server reports a `content-length`.
  final int? sizeBytes;
}

/// A complete on-device OCR model: a text-detection network, a
/// text-recognition network, the recognizer's character dictionary, and an
/// optional orientation classifier — the four pieces of a classic
/// detect-then-recognize OCR pipeline (PP-OCR family).
@immutable
class PdfOcrModel {
  const PdfOcrModel({
    required this.id,
    required this.displayName,
    required this.detection,
    required this.recognition,
    required this.dictionary,
    this.classification,
    this.description = '',
    this.languages = const ['en'],
    this.recognitionImageHeight = 48,
    this.detectionSideLimit = 960,
    this.detectionMean = const [0.485, 0.456, 0.406],
    this.detectionStd = const [0.229, 0.224, 0.225],
  });

  /// A stable identifier — also the model's cache sub-directory name, so keep
  /// it filesystem-safe (letters, digits, `-`, `_`).
  final String id;

  /// A human-readable name shown in download UI.
  final String displayName;

  /// One-line description for UI / docs.
  final String description;

  /// ISO language codes the recognizer's dictionary covers (informational).
  final List<String> languages;

  /// The text-detection network (DB-style probability map output).
  final PdfOcrModelFile detection;

  /// The text-recognition network (CRNN/CTC-style logits output).
  final PdfOcrModelFile recognition;

  /// The recognizer's character dictionary (one token per line).
  final PdfOcrModelFile dictionary;

  /// Optional angle classifier (0/180) — omitted by default.
  final PdfOcrModelFile? classification;

  /// The fixed input height the recognizer expects (PP-OCRv5 = 48).
  final int recognitionImageHeight;

  /// Detection resizes the page so its longest side is at most this many
  /// pixels (rounded to a multiple of 32). Higher = more accurate on small
  /// type, slower.
  final int detectionSideLimit;

  /// Per-channel normalization mean (RGB) for the detection input.
  final List<double> detectionMean;

  /// Per-channel normalization standard deviation (RGB) for the detection
  /// input.
  final List<double> detectionStd;

  /// Every file this model needs downloaded, detection first (so progress
  /// counts them in a stable order).
  List<PdfOcrModelFile> get files => [
        detection,
        recognition,
        dictionary,
        if (classification != null) classification!,
      ];

  /// The summed [PdfOcrModelFile.sizeBytes] when every file declares one,
  /// else null.
  int? get approxSizeBytes {
    var total = 0;
    for (final f in files) {
      final s = f.sizeBytes;
      if (s == null) return null;
      total += s;
    }
    return total;
  }
}

/// Built-in model descriptors.
///
/// **Hosting note.** ONNX OCR bundles are not tiny binaries this repository
/// ships in-tree, so the default [ppOcrV5Mobile] points its file URLs at
/// release assets you publish yourself (the package README has the exact
/// `paddle2onnx` conversion + upload recipe). Until those assets exist the
/// download will 404 with a clear error; swap in your own [PdfOcrModel] (any
/// URLs + SHA-256s) via [PdfOcrModelManager] / [OnDeviceOcrEngine] at any
/// time.
abstract final class PdfOcrModels {
  PdfOcrModels._();

  /// Base URL the default bundle's files hang off. Override the whole model
  /// to point elsewhere.
  static final Uri _defaultBundleBase = Uri.parse(
    'https://github.com/ben-milanko/dart-pdf/releases/download/ocr-models-v1/',
  );

  /// PP-OCRv5 *mobile* — the small (~5M-parameter, ~15 MB total) classic
  /// detect+recognize pipeline. Runs on CPU on every supported platform; the
  /// recommended offline default. Latin/English dictionary.
  static final PdfOcrModel ppOcrV5Mobile = PdfOcrModel(
    id: 'pp-ocrv5-mobile-en',
    displayName: 'PP-OCRv5 mobile (English/Latin)',
    description: 'Lightweight on-device OCR (PaddleOCR PP-OCRv5 mobile). '
        'Runs offline on CPU.',
    languages: const ['en'],
    detection: PdfOcrModelFile(
      name: 'det.onnx',
      url: _defaultBundleBase.resolve('PP-OCRv5_mobile_det.onnx'),
      sizeBytes: 4700000,
    ),
    recognition: PdfOcrModelFile(
      name: 'rec.onnx',
      url: _defaultBundleBase.resolve('PP-OCRv5_mobile_rec.onnx'),
      sizeBytes: 10400000,
    ),
    dictionary: PdfOcrModelFile(
      name: 'dict.txt',
      url: _defaultBundleBase.resolve('ppocrv5_dict.txt'),
      sizeBytes: 80000,
    ),
  );
}
