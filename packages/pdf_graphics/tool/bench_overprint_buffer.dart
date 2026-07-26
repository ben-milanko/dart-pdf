// Local A/B for the overprint colorant buffer's interpretation cost
// (issue #502): interprets a corpus with PdfInterpreter.debugResolveOverprint
// on and off through a null device and reports the ratio per file.
//
//   dart run tool/bench_overprint_buffer.dart <dir-or-file> [repeats]
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final root = args.isEmpty ? '../../test_corpora/ghent' : args[0];
  final repeats = args.length > 1 ? int.parse(args[1]) : 5;
  final files = <File>[];
  final entity = FileSystemEntity.typeSync(root);
  if (entity == FileSystemEntityType.directory) {
    files.addAll(Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.toLowerCase().endsWith('.pdf') && !f.path.contains('/_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path)));
  } else {
    files.add(File(root));
  }

  var totalOn = 0, totalOff = 0, buffered = 0;
  final perFile = <double>[];
  for (final file in files) {
    final bytes = file.readAsBytesSync();
    final ratios = <int>[];
    for (final resolve in [false, true]) {
      PdfInterpreter.debugResolveOverprint = resolve;
      final sw = Stopwatch()..start();
      for (var r = 0; r < repeats; r++) {
        final doc = PdfDocument.open(bytes);
        for (var i = 0; i < doc.pageCount; i++) {
          PdfInterpreter(cos: doc.cos, device: _NullDevice())
              .drawPage(doc.page(i));
        }
      }
      ratios.add(sw.elapsedMicroseconds);
    }
    totalOff += ratios[0];
    totalOn += ratios[1];
    final ratio = ratios[0] == 0 ? 1.0 : ratios[1] / ratios[0];
    perFile.add(ratio);
    if (ratio > 1.15) buffered++;
    if (ratio > 1.15) {
      stdout.writeln('${ratio.toStringAsFixed(2)}x  '
          '${file.path.split('/').last}  '
          '(${(ratios[0] / repeats / 1000).toStringAsFixed(1)}ms -> '
          '${(ratios[1] / repeats / 1000).toStringAsFixed(1)}ms)');
    }
  }
  PdfInterpreter.debugResolveOverprint = true;
  perFile.sort();
  final median = perFile.isEmpty ? 1.0 : perFile[perFile.length ~/ 2];
  stdout.writeln('--- median ${median.toStringAsFixed(3)}x | '
      '${files.length} files, $buffered above 1.15x, '
      'total ${(totalOn / totalOff).toStringAsFixed(3)}x '
      '(${(totalOff / 1000).toStringAsFixed(0)}ms -> '
      '${(totalOn / 1000).toStringAsFixed(0)}ms)');
}

/// Every callback implemented explicitly: a `noSuchMethod` stand-in costs more
/// per call than the buffer being measured, which flatters the ratio.
class _NullDevice implements PdfDevice {
  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {}
  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {}
  @override
  void fillMesh(PdfMesh mesh, double alpha) {}
  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {}
  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawText(PdfTextRun run) {}
  @override
  void drawImage(PdfImageRequest request) {}
  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {}
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
  }) =>
      drawMask();
}
