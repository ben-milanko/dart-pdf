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
/// ships in-tree, so the default [ppOcrV5Mobile] points its file URLs at the
/// `ocr-models-v1` GitHub release (PP-OCRv5 mobile converted to ONNX; see the
/// package README for the `paddle2onnx` recipe and Apache-2.0 attribution).
/// To host the bundle elsewhere — or use a different model — swap in your own
/// [PdfOcrModel] (any URLs + SHA-256s) via [PdfOcrModelManager] /
/// [OnDeviceOcrEngine] at any time.
abstract final class PdfOcrModels {
  PdfOcrModels._();

  /// Base URL the default bundle's files hang off. Override the whole model
  /// to point elsewhere.
  static final Uri _defaultBundleBase = Uri.parse(
    'https://github.com/ben-milanko/dart-pdf/releases/download/ocr-models-v1/',
  );

  /// PP-OCRv5 *mobile* — the small (~5M-parameter, ~21 MB total) classic
  /// detect+recognize pipeline. Runs on CPU on every supported platform; the
  /// recommended offline default. Multilingual dictionary (CJK + Latin), so
  /// it reads English/Latin scans out of the box.
  ///
  /// The bundle is hosted on the `ocr-models-v1` GitHub release, so every
  /// file carries its `sha256` and a corrupted or tampered download is
  /// rejected. The `.onnx` files are the official PaddlePaddle PP-OCRv5 mobile
  /// models converted to ONNX with `paddle2onnx`; the dictionary is the
  /// recognizer's character list. All Apache-2.0 (see the release's
  /// `NOTICE.txt` and the package README for attribution).
  static final PdfOcrModel ppOcrV5Mobile = PdfOcrModel(
    id: 'pp-ocrv5-mobile',
    displayName: 'PP-OCRv5 mobile (multilingual)',
    description: 'Lightweight on-device OCR (PaddleOCR PP-OCRv5 mobile). '
        'Runs offline on CPU.',
    languages: const ['en'],
    detection: PdfOcrModelFile(
      name: 'det.onnx',
      url: _defaultBundleBase.resolve('PP-OCRv5_mobile_det.onnx'),
      sha256:
          'd5de5df358366210d16419b9636a2fc1efa5d7a20688f38a7869ec7b1a4f4f7d',
      sizeBytes: 4819576,
    ),
    recognition: PdfOcrModelFile(
      name: 'rec.onnx',
      url: _defaultBundleBase.resolve('PP-OCRv5_mobile_rec.onnx'),
      sha256:
          '0030c6b05fbe29b07a93701503938d637efe7423325e2efb2bd7c8f220d40a8d',
      sizeBytes: 16557298,
    ),
    dictionary: PdfOcrModelFile(
      name: 'dict.txt',
      url: _defaultBundleBase.resolve('ppocrv5_dict.txt'),
      sha256:
          'd1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b',
      sizeBytes: 74012,
    ),
  );
}
