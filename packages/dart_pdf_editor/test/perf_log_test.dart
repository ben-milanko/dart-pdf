import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The first enabled log registers a SchedulerBinding timings callback
  // (for frame JANK), so the binding must exist.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Captures everything printed during [body] — PdfPerfLog flushes through
  // the top-level print(), which honours the current Zone.
  List<String> capturePrints(void Function() body) {
    final lines = <String>[];
    runZoned(body,
        zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => lines.add(line)));
    return lines;
  }

  tearDown(() => PdfPerfLog.enabled = false);

  test('disabled — log emits nothing', () {
    PdfPerfLog.enabled = false;
    expect(capturePrints(() => PdfPerfLog.log('nope')), isEmpty);
  });

  test('enabled — each line prints immediately and synchronously', () {
    // No frame is pumped here, so a buffered, frame-flushed log would emit
    // nothing — exactly the freeze blind spot this guards against. The lines
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
}
