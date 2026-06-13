import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A resolution-independent snapshot of a [PdfViewer]'s scroll position
/// and zoom — enough to reopen the same document where the user left it.
///
/// The position is stored as the page at the top-left of the viewport
/// plus fractional offsets into that page (0–1, y-down), not as raw
/// pixels, so it restores correctly at any window size. Capture one with
/// `PdfViewerController.captureViewport` and restore it with
/// `PdfViewerController.restoreViewport` or `PdfViewer.initialViewport`.
@immutable
class PdfViewport {
  const PdfViewport({
    required this.page,
    this.top = 0,
    this.left = 0,
    this.zoom = 1,
  });

  /// Zero-based index of the page at the viewport's top edge.
  final int page;

  /// Fraction down [page] (0–1, y-down) where the viewport's top edge
  /// sits.
  final double top;

  /// Fraction across [page] where the viewport's left edge sits. Only
  /// meaningful while zoomed in past fit-width; below it the page is
  /// centered and this is ignored on restore.
  final double left;

  /// The effective zoom factor (1 = fit width; below 1 the pages lay out
  /// smaller so more of the document is on screen).
  final double zoom;

  Map<String, Object?> toJson() => {
        'page': page,
        if (top != 0) 'top': top,
        if (left != 0) 'left': left,
        'zoom': zoom,
      };

  /// Rebuilds a viewport from [toJson] output, or null when the map is
  /// malformed.
  static PdfViewport? fromJson(Map<String, Object?> json) {
    final page = json['page'];
    if (page is! int || page < 0) return null;
    return PdfViewport(
      page: page,
      top: (json['top'] as num?)?.toDouble() ?? 0,
      left: (json['left'] as num?)?.toDouble() ?? 0,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
    );
  }

  String encode() => jsonEncode(toJson());

  /// Parses [encode] output, or null when the string is not valid.
  static PdfViewport? decode(String source) {
    try {
      final json = jsonDecode(source);
      return json is Map<String, Object?> ? fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PdfViewport &&
      other.page == page &&
      other.top == top &&
      other.left == left &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(page, top, left, zoom);

  @override
  String toString() =>
      'PdfViewport(page: $page, top: $top, left: $left, zoom: $zoom)';
}

/// A stable key identifying a PDF by its content, for persisting a
/// per-document viewport (see `PdfReader.documentId`).
///
/// Hashes the byte length plus a scattering of sampled bytes, so it stays
/// cheap on large CAD/scan files while still telling different documents
/// apart. Hosts that already have a stable identifier (a file path or
/// URL) should pass that instead.
String pdfDocumentKey(Uint8List bytes) {
  // FNV-1a over the length and up to ~4 KB sampled evenly across the file
  var hash = 0x811c9dc5;
  void mix(int byte) {
    hash ^= byte & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }

  final length = bytes.length;
  mix(length);
  mix(length >> 8);
  mix(length >> 16);
  mix(length >> 24);
  const sampleBudget = 4096;
  if (length <= sampleBudget) {
    for (final b in bytes) {
      mix(b);
    }
  } else {
    final stride = length ~/ sampleBudget;
    for (var i = 0; i < length; i += stride) {
      mix(bytes[i]);
    }
  }
  return hash.toRadixString(16);
}
