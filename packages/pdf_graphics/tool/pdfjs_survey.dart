// Survey harness for the pdf.js corpus: opens every file, interprets every
// page, and buckets the outcomes so the corpus test expectations can be
// pinned from reality. Throwaway diagnostics — not part of the test suite.
//
// Usage: fvm dart tool/pdfjs_survey.dart
import 'dart:convert';
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const passwords = {
  'issue6010_1.pdf': 'abc',
  'issue6010_2.pdf': 'æøå',
  'issue15893_reduced.pdf': 'test',
  'bug1782186.pdf': 'Hello',
  'issue3371.pdf': 'ELXRTQWS',
  'encrypted-attachment.pdf': '000000',
};

void main() {
  final root = Directory('../../test_corpora/pdfjs');
  final files = root
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final report = <String, Object?>{};
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final entry = <String, Object?>{};
    report[name] = entry;
    final sw = Stopwatch()..start();
    PdfDocument doc;
    try {
      doc = PdfDocument.open(file.readAsBytesSync(),
          password: passwords[name] ?? '');
    } catch (e) {
      entry['open'] = 'THROW ${e.runtimeType}: ${_clip(e)}';
      continue;
    }
    int pageCount;
    try {
      pageCount = doc.pageCount;
    } catch (e) {
      entry['open'] = 'THROW(pageCount) ${e.runtimeType}: ${_clip(e)}';
      continue;
    }
    entry['pages'] = pageCount;
    final pageErrors = <String>[];
    var blank = 0;
    for (var i = 0; i < pageCount && i < 25; i++) {
      try {
        final page = doc.page(i);
        final device = CountingDevice();
        PdfInterpreter(cos: doc.cos, device: device)
          ..drawPage(page)
          ..drawAnnotations(page);
        if (device.paintOps == 0) blank++;
      } catch (e) {
        pageErrors.add('p$i ${e.runtimeType}: ${_clip(e)}');
      }
    }
    if (pageErrors.isNotEmpty) entry['errors'] = pageErrors;
    if (blank > 0) entry['blankPages'] = blank;
    entry['ms'] = sw.elapsedMilliseconds;
  }
  File('/tmp/pdfjs_survey.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
  // summary to stdout
  var ok = 0, openFail = 0, pageFail = 0, blanks = 0, slow = 0;
  report.forEach((name, e) {
    final m = e as Map<String, Object?>;
    if (m.containsKey('open')) {
      openFail++;
      stdout.writeln('OPEN-FAIL $name: ${m['open']}');
    } else if (m.containsKey('errors')) {
      pageFail++;
      stdout.writeln('PAGE-FAIL $name: ${(m['errors'] as List).join('; ')}');
    } else {
      ok++;
      if (m.containsKey('blankPages')) {
        blanks++;
        stdout.writeln('BLANK     $name (${m['blankPages']} pages)');
      }
    }
    if ((m['ms'] as int? ?? 0) > 3000) {
      slow++;
      stdout.writeln('SLOW      $name ${m['ms']}ms');
    }
  });
  stdout.writeln('--- ok: $ok (blank-page files: $blanks), '
      'open failures: $openFail, page failures: $pageFail, slow: $slow');
}

String _clip(Object e) {
  final s = e.toString().replaceAll('\n', ' ');
  return s.length > 140 ? s.substring(0, 140) : s;
}

/// Counts paint callbacks, recursing into soft-mask groups.
class CountingDevice implements PdfDevice {
  int paintOps = 0;

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    paintOps++;
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    paintOps++;
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    paintOps++;
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    paintOps++;
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawText(PdfTextRun run) {
    if (!run.invisible) paintOps++;
  }

  @override
  void drawImage(PdfImageRequest request) {
    paintOps++;
  }

  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {
    drawMask();
  }
}
