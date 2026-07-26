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

  tearDown(() {
    PdfPerfLog.enabled = false;
    PdfPerfLog.sink = null;
  });

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
          elapsedMs: 912.34,
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
    // The measured duration of the rasterize call itself - the figure that
    // used to require inferring gaps between log timestamps.
    expect(lines[0], contains('ms=912.3'));
    expect(lines[0], matches(RegExp(r'rss=\d+MB')));

    // A full-page raster carries no region, and the sequence number advances so
    // a per-frame raster loop is visible as `n` racing up. Without a measured
    // duration the ms field stays off the line, keeping older call sites'
    // output unchanged.
    expect(lines[1], contains('raster kind=base-full page=2'));
    expect(lines[1], contains(' full '));
    expect(lines[1], isNot(contains('region=')));
    expect(lines[1], isNot(contains('ms=')));

    int seq(String line) =>
        int.parse(RegExp(r'n=(\d+)').firstMatch(line)!.group(1)!);
    expect(seq(lines[1]), seq(lines[0]) + 1);
  });

  test('sink receives every line while enabled, in addition to the console',
      () {
    final forwarded = <String>[];
    final lines = capturePrints(() {
      PdfPerfLog.sink = forwarded.add;
      PdfPerfLog.enabled = true;
      PdfPerfLog.log('alpha');
      PdfPerfLog.log('beta');
    });
    // The console path must survive the sink being attached - hosts mirror,
    // they don't redirect.
    expect(lines, hasLength(2));
    expect(forwarded, hasLength(2));
    expect(forwarded[0], startsWith('[perf '));
    expect(forwarded[0], contains('alpha'));
    expect(forwarded[1], contains('beta'));
  });

  test('sink is not consulted while disabled', () {
    var calls = 0;
    PdfPerfLog.sink = (_) => calls++;
    PdfPerfLog.enabled = false;
    PdfPerfLog.log('nope');
    expect(calls, 0);
  });

  test('a throwing sink does not propagate to the caller', () {
    capturePrints(() {
      PdfPerfLog.sink = (_) => throw StateError('host bug');
      PdfPerfLog.enabled = true;
      // Rendering must never break because a host's forwarding closure is
      // broken - the log call itself must complete cleanly.
      expect(() => PdfPerfLog.log('alpha'), returnsNormally);
    });
  });
  test('interpret splits the worker wait from the picture build', () {
    final lines = capturePrints(() {
      PdfPerfLog.enabled = true;
      PdfPerfLog.interpret(0,
          path: 'worker', interpretMs: 2588.9, waitMs: 934.2, buildMs: 1228.7);
      // Older call sites pass neither; the line must stay as it was so
      // existing traces remain comparable.
      PdfPerfLog.interpret(1, path: 'recorded', interpretMs: 42.0);
    });

    expect(lines[0], contains('interpret=2588.9ms'));
    expect(lines[0], contains('wait=934.2ms'));
    expect(lines[0], contains('build=1228.7ms'));

    expect(lines[1], contains('interpret=42.0ms'));
    expect(lines[1], isNot(contains('wait=')));
    expect(lines[1], isNot(contains('build=')));
  });

  test('interpret splits the build phase into decode and construction', () {
    final lines = capturePrints(() {
      PdfPerfLog.enabled = true;
      PdfPerfLog.interpret(0,
          path: 'worker',
          interpretMs: 1652.3,
          waitMs: 36.3,
          buildMs: 1055.8,
          decodeMs: 1021.4,
          replayMs: 32.9);
      // Fused call sites (the local 'recorded' path decodes and constructs in
      // one walk) pass neither, and a lone half is meaningless - so the pair
      // is all-or-nothing.
      PdfPerfLog.interpret(1,
          path: 'recorded', interpretMs: 42.0, waitMs: 0, buildMs: 42.0);
      PdfPerfLog.interpret(2,
          path: 'worker', interpretMs: 10.0, decodeMs: 5.0);
    });

    expect(lines[0], contains('build=1055.8ms'));
    expect(lines[0], contains('decode=1021.4ms'));
    expect(lines[0], contains('replay=32.9ms'));

    expect(lines[1], contains('build=42.0ms'));
    expect(lines[1], isNot(contains('decode=')));
    expect(lines[1], isNot(contains('replay=')));

    expect(lines[2], isNot(contains('decode=')),
        reason: 'a decode without a replay must not print half a split');
  });

  test('interpret splits substituted-text shaping out of replay', () {
    final lines = capturePrints(() {
      PdfPerfLog.enabled = true;
      PdfPerfLog.interpret(0,
          path: 'worker',
          interpretMs: 48.0,
          waitMs: 4.0,
          buildMs: 44.0,
          decodeMs: 0.0,
          replayMs: 43.5,
          textShapeMs: 33.0,
          textShapeMiss: 660,
          textShapeHit: 0);
      // Call sites without the split (no retained-scene replay, or the log's
      // off) pass no textShapeMs, and the shape fields stay off the line.
      PdfPerfLog.interpret(1,
          path: 'worker',
          interpretMs: 10.0,
          waitMs: 1.0,
          buildMs: 9.0,
          decodeMs: 0.0,
          replayMs: 9.0);
    });

    expect(lines[0], contains('replay=43.5ms'));
    expect(lines[0], contains('shape=33.0ms'));
    expect(lines[0], contains('shaped=660'));
    expect(lines[0], contains('cached=0'));

    expect(lines[1], contains('replay=9.0ms'));
    expect(lines[1], isNot(contains('shape=')));
    expect(lines[1], isNot(contains('shaped=')));
  });
}
