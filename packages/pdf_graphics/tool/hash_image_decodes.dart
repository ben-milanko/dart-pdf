// Hashes the decoded pixels of every image XObject across a set of PDFs, so a
// change to the decode path can be proved byte-identical:
//
//   fvm dart run tool/hash_image_decodes.dart ../../test_corpora/*/*.pdf > after.txt
//   # ...check out the old code in a worktree, run it there...
//   diff <(sort before.txt) <(sort after.txt)
//
// Pass --alternate-only to restrict the sweep to Separation/DeviceN images
// (the tint-transform path). Unfixed decode paths can be slow enough that the
// sweep needs sharding across cores to finish; split the file list and diff the
// concatenation.
//
// Both entry points are hashed on purpose. decodePdfImagePixels returns null
// for a base paired with a DCTDecode /SMask, and the dart:ui layer then decodes
// the base itself - so hashing only the first silently skips those images.
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// FNV-1a over the decoded pixels - no dependency, and collisions do not
/// matter for an equal/not-equal check against the same data.
String _fnv(List<int> bytes) {
  var h = 0xcbf29ce484222325;
  for (final b in bytes) {
    h = (h ^ b) * 0x100000001b3;
    h &= 0xFFFFFFFFFFFFFFFF;
  }
  return h.toRadixString(16);
}

/// Whether this image decodes through the Separation/DeviceN tint transform.
bool _isAlternate(CosDocument cos, CosDictionary dict) {
  final cs = cos.resolve(dict['ColorSpace']);
  if (cs is! CosArray || cs.length == 0) return false;
  final family = cos.resolve(cs[0]);
  return family is CosName &&
      (family.value == 'DeviceN' || family.value == 'Separation');
}

class _Collect implements PdfDevice {
  final streams = <PdfImageRequest>[];

  @override
  void drawImage(PdfImageRequest r) => streams.add(r);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main(List<String> args) {
  final alternateOnly = args.contains('--alternate-only');
  final paths = args.where((a) => !a.startsWith('--'));

  // Resume aids for long sweeps (the unfixed side of a comparison can be
  // slow enough to shard by page range): hash only pages in [min, max].
  final pageMin = int.tryParse(
          Platform.environment['PDF_HASH_PAGE_MIN'] ?? '') ??
      0;
  final pageMax =
      int.tryParse(Platform.environment['PDF_HASH_PAGE_MAX'] ?? '') ?? 1 << 30;

  for (final path in paths) {
    final name = path.split('/').last;
    final PdfDocument doc;
    final int pages;
    try {
      doc = PdfDocument.open(File(path).readAsBytesSync());
      // Corrupt files (the pdf.js suite includes fuzzed PDFs) can open and
      // then throw here; without the guard one such file kills the sweep and
      // silently truncates the output.
      pages = doc.pageCount;
    } catch (e) {
      stdout.writeln('$name OPEN-FAILED ${e.runtimeType}');
      continue;
    }
    for (var p = pageMin; p < pages && p <= pageMax; p++) {
      final collector = _Collect();
      try {
        // scanImagesOnly walks forms, Type3 glyphs, and tiling patterns, so it
        // sees images a page's own /Resources /XObject never lists.
        PdfInterpreter(cos: doc.cos, device: collector, scanImagesOnly: true)
            .drawPageOperations(doc.page(p),
                ContentStreamParser.parse(doc.page(p).contentBytes()));
      } catch (e) {
        stdout.writeln('$name p$p WALK-FAILED ${e.runtimeType}');
        continue;
      }
      for (var i = 0; i < collector.streams.length; i++) {
        final stream = collector.streams[i].stream;
        if (alternateOnly && !_isAlternate(doc.cos, stream.dictionary)) continue;

        String digest;
        try {
          final pixels = decodePdfImagePixels(doc.cos, stream);
          digest = pixels == null
              ? 'pixels:null'
              : 'pixels:${pixels.width}x${pixels.height}:${_fnv(pixels.rgba)}';
        } catch (e) {
          digest = 'pixels:THREW ${e.runtimeType}';
        }
        try {
          final base = decodePdfImageBase(doc.cos, stream);
          digest += base == null
              ? ' base:null'
              : ' base:${base.width}x${base.height}:'
                  '${base.opaque ? 'opaque' : 'alpha'}:${_fnv(base.rgba)}';
        } catch (e) {
          digest += ' base:THREW ${e.runtimeType}';
        }
        stdout.writeln('$name p$p i$i $digest');
      }
    }
  }
}
