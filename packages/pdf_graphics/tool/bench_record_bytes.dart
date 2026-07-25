// #451: what is actually *in* a render record, by bytes?
//
// The device trace (app 3.0.0+20, 62-page book, web release) showed a single
// page's record reaching 39 MB against a 96 MB record-cache budget - so three
// such pages fill the cache and every neighbour is evicted and re-recorded.
// The trace measured 575 MB of records produced for 20 distinct pages.
//
// This splits a record by bytes rather than time, into the decoded RGBA, the
// source image streams carried beside it, and everything else - plus the glyph
// outlines inside that remainder, which turned out to be the largest single
// item (151.7 MB of 394 MB over a 62-page book, 85% of it repetition).
//
//   fvm dart tool/bench_record_bytes.dart [dir-or-file ...]
//
// Defaults to the checked-in test corpora. `--json` emits machine-readable
// rows; `--budget=N` sets the assumed record-cache budget in MB (default 96,
// the viewer's pdfRenderWorkerCacheBudgetBytes).
import 'dart:convert';
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _ratio = 2.0;

void main(List<String> args) {
  final json = args.contains('--json');
  final budgetMB = double.tryParse(args
          .firstWhere((a) => a.startsWith('--budget='), orElse: () => '')
          .replaceFirst('--budget=', '')) ??
      96.0;
  final paths = args.where((a) => !a.startsWith('--')).toList();
  final files = _collect(paths.isEmpty
      ? const ['../../test_corpora/ghent', '../../test_corpora/pdfjs']
      : paths);
  if (files.isEmpty) {
    stderr.writeln('no PDFs found');
    exit(1);
  }

  final rows = <Map<String, Object?>>[];
  for (final file in files) {
    final PdfDocument doc;
    final CosDocument cos;
    final int pageCount;
    try {
      final bytes = File(file).readAsBytesSync();
      cos = CosDocument.open(bytes);
      doc = PdfDocument.open(bytes);
      pageCount = doc.pageCount;
    } catch (_) {
      continue;
    }
    for (var i = 0; i < pageCount; i++) {
      try {
        final row = _measurePage(doc, cos, i, file);
        if (row != null) rows.add(row);
      } catch (_) {
        // a page that will not interpret is not this tool's problem
      }
    }
  }

  if (json) {
    stdout.writeln(const JsonEncoder.withIndent(' ').convert(rows));
    return;
  }

  rows.sort((a, b) => (b['totalMB'] as num).compareTo(a['totalMB'] as num));
  stdout.writeln('\nRecord byte composition at ratio $_ratio '
      '(${rows.length} pages)\n');
  stdout.writeln('  totalMB   rgbaMB  outlnMB  dedupMB  '
      'glyphs/byValue/byIdentity  page');
  for (final r in rows.take(25)) {
    stdout.writeln('  ${_pad(r['totalMB'])}  ${_pad(r['rgbaMB'])}  '
        '${_pad(r['outlineMB'])}  ${_pad(r['dedupedOutlineMB'])}  '
        '${'${r['glyphs']}/${r['distinctOutlines']}/${r['identityOutlines']}'.padLeft(18)}  '
        '${r['page']}');
  }

  final total = rows.fold<double>(0, (a, r) => a + (r['totalMB'] as num));
  final rgba = rows.fold<double>(0, (a, r) => a + (r['rgbaMB'] as num));
  final stream = rows.fold<double>(0, (a, r) => a + (r['streamMB'] as num));
  stdout.writeln('\n${rows.length} pages: ${_round(total)} MB of records.');
  stdout.writeln('  ${_round(rgba)} MB (${(rgba / total * 100).round()}%) '
      'decoded RGBA');
  stdout.writeln('  ${_round(stream)} MB (${(stream / total * 100).round()}%) '
      'source image streams, carried *beside* the RGBA');
  stdout.writeln('  ${_round(total - rgba - stream)} MB '
      '(${((total - rgba - stream) / total * 100).round()}%) draw commands '
      'and other resources');

  final outline = rows.fold<double>(0, (a, r) => a + (r['outlineMB'] as num));
  final deduped =
      rows.fold<double>(0, (a, r) => a + (r['dedupedOutlineMB'] as num));
  final allGlyphs = rows.fold<int>(0, (a, r) => a + (r['glyphs'] as int));
  final distinct =
      rows.fold<int>(0, (a, r) => a + (r['distinctOutlines'] as int));
  final ident =
      rows.fold<int>(0, (a, r) => a + (r['identityOutlines'] as int));
  // These two are the *logical* cost of the outlines - what they would cost
  // written inline on every placement, and what they cost collapsed by shape.
  // Since #451 the writer collapses them, so the deduped figure is what the
  // record actually carries and the gap is what the dedup saves.
  stdout.writeln('\nGlyph outlines across $allGlyphs placements:');
  stdout.writeln('  ${_round(outline)} MB written inline per placement '
      '(the pre-#451 format)');
  stdout.writeln('  ${_round(deduped)} MB collapsed by shape, across '
      '$distinct distinct outlines');
  stdout.writeln('  -> ${_round(outline - deduped)} MB '
      '(${((1 - deduped / outline) * 100).round()}%) is repetition.');
  stdout.writeln('  Distinct by object identity (what a writer-side table '
      'would see without hashing): $ident vs $distinct by value.');

  // What the cache can hold. The viewer caches whole records, so a page's
  // image payload occupies the record budget for as long as the record is
  // retained - on top of the same pixels living in the decoded-image cache.
  final big = rows.where((r) => (r['totalMB'] as num) > budgetMB / 4).toList();
  stdout.writeln('${big.length} pages exceed a quarter of the '
      '${budgetMB.round()} MB record budget on their own'
      '${big.isEmpty ? '.' : ':'}');
  for (final r in big.take(10)) {
    stdout.writeln('  ${_pad(r['totalMB'])} MB  '
        '(${((r['totalMB'] as num) / budgetMB * 100).round()}% of budget)  '
        '${r['page']}');
  }
}

Map<String, Object?>? _measurePage(
    PdfDocument doc, CosDocument cos, int index, String path) {
  final page = doc.page(index);
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: cos, device: recorder)
    ..drawPage(page)
    ..drawAnnotations(page);
  final commands = recorder.commands;

  final record = serializeCommands(commands,
      cos: cos, decodeImages: true, maxImagePixelRatio: _ratio);
  if (record == null) return null;

  // Before serialization: does the font engine hand back the *same* PdfPath
  // for a repeated glyph? If so a writer-side table can dedupe on identity
  // alone, with no value hashing in the hot path.
  final identityOutlines = Set<PdfPath>.identity();
  for (final c in commands) {
    if (c is! PdfDrawTextCommand) continue;
    for (final g in c.run.glyphs ?? const <PdfGlyphPlacement>[]) {
      if (g.outline != null) identityOutlines.add(g.outline!);
    }
  }

  // Measure the payload exactly rather than by differencing against a
  // decodeImages:false run - that run still embeds every image's *encoded*
  // stream, so the difference attributes those bytes to the commands.
  //
  // A record carries both halves for each image: the premultiplied RGBA the
  // worker decoded, and the source stream beside it (device.dart:194 - "the
  // [stream] is still serialized so the decoded pixels cache by content").
  var rgbaBytes = 0, streamBytes = 0, decodedImages = 0;
  // Glyph outlines ride on every *placement* (device.dart:50), so a letter
  // used 500 times serializes its outline 500 times. Count both the bytes
  // they cost and what they would cost deduplicated by shape.
  var glyphs = 0, outlineBytes = 0;
  final distinctOutlines = <String, int>{};
  for (final c in deserializeCommands(record)) {
    if (c is PdfDrawImageCommand) {
      final decoded = c.request.decoded;
      if (decoded != null) {
        rgbaBytes += decoded.rgba.length;
        decodedImages++;
      }
      streamBytes += c.request.stream.rawBytes.length;
    } else if (c is PdfDrawTextCommand) {
      for (final g in c.run.glyphs ?? const <PdfGlyphPlacement>[]) {
        final outline = g.outline;
        if (outline == null) continue;
        glyphs++;
        final bytes = _pathBytes(outline);
        outlineBytes += bytes;
        distinctOutlines[_pathKey(outline)] = bytes;
      }
    }
  }
  final dedupedOutlineBytes =
      distinctOutlines.values.fold<int>(0, (a, b) => a + b);

  const mb = 1 << 20;
  final totalMB = record.length / mb;
  final rgbaMB = rgbaBytes / mb;
  final streamMB = streamBytes / mb;
  return <String, Object?>{
    'page': '${path.split('/').last} p$index',
    'totalMB': _round(totalMB),
    'rgbaMB': _round(rgbaMB),
    'streamMB': _round(streamMB),
    'otherMB': _round(totalMB - rgbaMB - streamMB),
    'rgbaPct': totalMB <= 0 ? 0 : (rgbaMB / totalMB * 100).round(),
    'images': recorder.imageRequests.length,
    'decodedImages': decodedImages,
    'commands': commands.length,
    'glyphs': glyphs,
    'distinctOutlines': distinctOutlines.length,
    'identityOutlines': identityOutlines.length,
    'outlineMB': _round(outlineBytes / mb),
    'dedupedOutlineMB': _round(dedupedOutlineBytes / mb),
  };
}

/// Bytes [_writePath] spends on [path]: a tag per segment plus float32 per
/// coordinate (render_command_codec.dart - "Path coordinates are carried at
/// float32 precision").
int _pathBytes(PdfPath path) {
  var bytes = 0;
  for (final s in path.segments) {
    bytes += switch (s) {
      PdfMoveTo() || PdfLineTo() => 1 + 8,
      PdfCubicTo() => 1 + 24,
      PdfClosePath() => 1,
    };
  }
  return bytes;
}

/// Identifies an outline by shape, so the same glyph drawn twice collapses.
String _pathKey(PdfPath path) {
  final b = StringBuffer();
  for (final s in path.segments) {
    switch (s) {
      case PdfMoveTo(:final x, :final y):
        b.write('M$x,$y;');
      case PdfLineTo(:final x, :final y):
        b.write('L$x,$y;');
      case PdfCubicTo(:final x1, :final y1, :final x2, :final y2, :final x3,
            :final y3):
        b.write('C$x1,$y1,$x2,$y2,$x3,$y3;');
      case PdfClosePath():
        b.write('Z;');
    }
  }
  return b.toString();
}

String _pad(Object? v) => (v as num).toStringAsFixed(1).padLeft(7);

double _round(double v) => (v * 10).round() / 10;

List<String> _collect(List<String> paths) {
  final out = <String>[];
  for (final p in paths) {
    final dir = Directory(p);
    if (dir.existsSync()) {
      for (final e in dir.listSync(recursive: true)) {
        if (e is File && e.path.toLowerCase().endsWith('.pdf')) out.add(e.path);
      }
    } else if (File(p).existsSync()) {
      out.add(p);
    }
  }
  out.sort();
  return out;
}
