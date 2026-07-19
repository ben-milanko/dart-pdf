import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The first enabled log registers a SchedulerBinding timings callback
  // (for frame JANK), so the binding must exist.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Captures everything printed during [body] - PdfPerfLog flushes through
  // the top-level print(), which honours the current Zone.
  List<String> capturePrints(void Function() body) {
    final lines = <String>[];
    runZoned(body,
        zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => lines.add(line)));
    return lines;
  }

  tearDown(() => PdfPerfLog.enabled = false);

  test('disabled - log emits nothing', () {
    PdfPerfLog.enabled = false;
    expect(capturePrints(() => PdfPerfLog.log('nope')), isEmpty);
  });

  test('enabled - each line prints immediately and synchronously', () {
    // No frame is pumped here, so a buffered, frame-flushed log would emit
    // nothing - exactly the freeze blind spot this guards against. The lines
    // must reach the console within the synchronous call.
    final lines = capturePrints(() {
      PdfPerfLog.enabled = true;
      PdfPerfLog.log('alpha');
      PdfPerfLog.log('beta');
    });
    expect(lines, hasLength(2));
    expect(lines[0], startsWith('[perf '));
    expect(lines[0], contains('alpha'));
    expect(lines[1], contains('beta'));
  });

  test('rssSuffix reads nothing while the log is off', () {
    // Call sites interpolate this into a log message *argument*, which Dart
    // evaluates before log() can check `enabled` - so without the guard every
    // one of them would pay a ProcessInfo.currentRss syscall on an ordinary
    // run. The empty string is what keeps that off the hot path.
    PdfPerfLog.enabled = false;
    expect(PdfPerfLog.rssSuffix(), isEmpty);
  });

  test('rssSuffix reports the process RSS while the log is on', () {
    PdfPerfLog.enabled = true;
    // dart:io reports RSS on the VM, so this is the real reading; on the web
    // the conditional import yields null and the suffix stays empty.
    expect(PdfPerfLog.rssSuffix(), matches(RegExp(r'^ rss=\d+MB$')));
  });

  test('raster emits nothing while the log is off', () {
    expect(
      capturePrints(() {
        PdfPerfLog.enabled = false;
        PdfPerfLog.raster('base-full',
            page: 0, imageWidth: 8192, imageHeight: 812, ratio: 1);
      }),
      isEmpty,
    );
  });

  test('raster reports size, sequence, and RSS for region and full rasters',
      () {
    final lines = capturePrints(() {
      PdfPerfLog.enabled = true;
      PdfPerfLog.raster('detail-picture',
          page: 0,
          imageWidth: 4730,
          imageHeight: 3548,
          ratio: 41.2,
          region: (width: 115, height: 86));
      PdfPerfLog.raster('base-full',
          page: 2, imageWidth: 8192, imageHeight: 812, ratio: 1);
    });
    expect(lines, hasLength(2));

    // A region raster: the megapixel figure is what distinguishes "one giant
    // allocation" from "a loop of small ones" when reading a device trace.
    expect(lines[0], contains('raster kind=detail-picture page=0'));
    expect(lines[0], contains('region=115x86pt'));
    expect(lines[0], contains('ratio=41.2'));
    expect(lines[0], contains('img=4730x3548 (16.8MP)'));
    expect(lines[0], matches(RegExp(r'rss=\d+MB')));

    // A full-page raster carries no region, and the sequence number advances so
    // a per-frame raster loop is visible as `n` racing up.
    expect(lines[1], contains('raster kind=base-full page=2'));
    expect(lines[1], contains(' full '));
    expect(lines[1], isNot(contains('region=')));

    int seq(String line) =>
        int.parse(RegExp(r'n=(\d+)').firstMatch(line)!.group(1)!);
    expect(seq(lines[1]), seq(lines[0]) + 1);
  });
}
