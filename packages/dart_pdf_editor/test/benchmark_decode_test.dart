// Cold-decode hotspot probe: buckets every corpus image by codec category
// (filter + colour space + bit depth + mask kind) and times a fresh,
// cache-disabled decode of each, so the dominant categories are visible.
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_DIR=../../corpus PDF_BENCHMARK_MAX_PAGES=0 \
//     fvm flutter test test/benchmark_decode_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/src/image_decoder.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

String _category(CosDocument cos, CosStream stream) {
  final dict = stream.dictionary;
  List<String> filters() {
    final f = cos.resolve(dict['Filter']);
    if (f is CosName) return [f.value];
    if (f is CosArray) {
      return [
        for (final e in f.items)
          if (cos.resolve(e) case CosName(:final value)) value,
      ];
    }
    return const [];
  }

  final fs = filters();
  final filter = fs.isEmpty ? 'raw' : fs.last;
  final isMask = cos.resolve(dict['ImageMask']) == const CosBoolean(true);
  if (isMask) return 'ImageMask';

  String family(CosObject? raw) {
    final s = cos.resolve(raw);
    if (s is CosName) {
      return switch (s.value) {
        'G' => 'Gray',
        'RGB' => 'RGB',
        'CMYK' => 'CMYK',
        'I' => 'Indexed',
        'DeviceGray' => 'Gray',
        'DeviceRGB' => 'RGB',
        'DeviceCMYK' => 'CMYK',
        final n => n,
      };
    }
    if (s is CosArray && s.length > 0) {
      final fam = cos.resolve(s[0]);
      if (fam is CosName) {
        if (fam.value == 'ICCBased' && s.length > 1) {
          final prof = cos.resolve(s[1]);
          if (prof is CosStream) {
            final n = cos.resolve(prof.dictionary['N']);
            final nn = n is CosInteger ? n.value : 3;
            return 'ICC$nn';
          }
        }
        return fam.value;
      }
    }
    return '?';
  }

  final space = family(dict['ColorSpace']);
  final bits = cos.resolve(dict['BitsPerComponent']);
  final bpc = bits is CosInteger ? bits.value : 8;
  final hasSMask = cos.resolve(dict['SMask']) is CosStream;
  final hasMask = dict['Mask'] != null;
  final mask = hasSMask ? '+SMask' : (hasMask ? '+Mask' : '');
  return '$filter/$space/${bpc}b$mask';
}

void main() {
  final dir = Platform.environment['PDF_BENCHMARK_DIR'];
  final maxPages =
      int.tryParse(Platform.environment['PDF_BENCHMARK_MAX_PAGES'] ?? '') ?? 0;

  testWidgets('cold decode hotspots by category', (tester) async {
    if (dir == null) {
      markTestSkipped('set PDF_BENCHMARK_DIR');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final catUs = <String, int>{};
      final catCount = <String, int>{};
      final catPixels = <String, int>{};
      var totalUs = 0;
      var totalImages = 0;
      // Dedup identical XObject streams within a doc (the cache would).
      for (final file in files) {
        PdfDocument doc;
        try {
          doc = PdfDocument.open(file.readAsBytesSync());
        } catch (_) {
          continue;
        }
        final limit = maxPages <= 0
            ? doc.pageCount
            : (doc.pageCount < maxPages ? doc.pageCount : maxPages);
        final seen = <CosStream>{};
        for (var i = 0; i < limit; i++) {
          try {
            final page = doc.page(i);
            final cos = page.document.cos;
            final collector = ImageCollector();
            PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
              ..drawPageOperations(
                  page, ContentStreamParser.parse(page.contentBytes()))
              ..drawAnnotations(page);
            for (final req in collector.streams) {
              if (req.isInline) continue;
              if (!seen.add(req.stream)) continue;
              final cat = _category(cos, req.stream);
              final sw = Stopwatch()..start();
              final images =
                  await decodeImages(cos, [req], cache: null);
              final us = sw.elapsedMicroseconds;
              var px = 0;
              for (final im in images.values) {
                px += im.width * im.height;
                im.dispose();
              }
              catUs[cat] = (catUs[cat] ?? 0) + us;
              catCount[cat] = (catCount[cat] ?? 0) + 1;
              catPixels[cat] = (catPixels[cat] ?? 0) + px;
              totalUs += us;
              totalImages++;
            }
          } catch (_) {}
        }
      }

      final keys = catUs.keys.toList()
        ..sort((a, b) => catUs[b]!.compareTo(catUs[a]!));
      // ignore: avoid_print
      print('\n=== cold decode by category '
          '($totalImages images, ${(totalUs / 1000).toStringAsFixed(0)} ms total) ===');
      // ignore: avoid_print
      print('  ${'category'.padRight(28)} ${'ms'.padLeft(8)} '
          '${'%'.padLeft(4)} ${'imgs'.padLeft(5)} ${'Mpx'.padLeft(7)} '
          '${'ns/px'.padLeft(7)}');
      for (final k in keys) {
        final ms = (catUs[k]! / 1000).toStringAsFixed(1);
        final pct = (catUs[k]! / totalUs * 100).toStringAsFixed(0);
        final mpx = (catPixels[k]! / 1e6).toStringAsFixed(2);
        final nspx = catPixels[k]! == 0
            ? '-'
            : (catUs[k]! * 1000 / catPixels[k]!).toStringAsFixed(1);
        // ignore: avoid_print
        print('  ${k.padRight(28)} ${ms.padLeft(8)} ${pct.padLeft(3)}% '
            '${catCount[k].toString().padLeft(5)} ${mpx.padLeft(7)} '
            '${nspx.padLeft(7)}');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}
