// Committing a revision must not scale with the size of the document.
//
// Each commit used to re-materialise the whole file (#413), so the cost of
// adding one annotation was O(file) - a 40 MB drawing copied 40 MB per ink
// stroke. The updater now returns only the appended tail and the controller
// appends it into the session buffer it already owns.
//
// The assertion compares per-revision cost across two base sizes rather than
// across time. That is the invariant that actually changed: a slope over
// revisions barely moves within one run (the tails are small next to the
// base), but the response to base size is 4x before and flat after.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Mean microseconds per commit over [revisions] highlight edits on [source].
double _perRevisionUs(Uint8List source, int revisions) {
  final editing = PdfEditingController(source);
  // Warm the path so the measured window is not paying JIT.
  for (var i = 0; i < 20; i++) {
    editing.apply((editor) =>
        editor.addHighlight(0, [const PdfRect(72, 72, 200, 88)]));
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < revisions; i++) {
    editing.apply((editor) => editor.addHighlight(0, [
          PdfRect(72, 72 + (i % 20) * 5.0, 200, 88 + (i % 20) * 5.0),
        ]));
  }
  sw.stop();
  editing.dispose();
  return sw.elapsedMicroseconds / revisions;
}

void main() {
  test('per-revision cost does not scale with document size', () {
    final small = Uint8List.fromList(buildSyntheticCadStrip(ops: 60000));
    final large = Uint8List.fromList(buildSyntheticCadStrip(ops: 240000));
    // Interleave the two so a machine that slows down mid-run skews both.
    final smallUs = _perRevisionUs(small, 150);
    final largeUs = _perRevisionUs(large, 150);
    final smallUs2 = _perRevisionUs(small, 150);
    final base = (smallUs + smallUs2) / 2;
    final ratio = largeUs / base;

    // ignore: avoid_print
    print('base ${(small.length / 1e6).toStringAsFixed(1)} MB -> '
        '${base.toStringAsFixed(0)} us/rev; '
        '${(large.length / 1e6).toStringAsFixed(1)} MB -> '
        '${largeUs.toStringAsFixed(0)} us/rev; ratio '
        '${ratio.toStringAsFixed(2)}x');

    expect(large.length, greaterThan(small.length * 3),
        reason: 'the two fixtures must differ enough to show the scaling');
    expect(ratio, lessThan(2.0),
        reason: 'per-revision cost scaled with document size - the O(file) '
            'copy per save is back (ratio ${ratio.toStringAsFixed(2)}x)');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
