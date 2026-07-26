// Widget-level progressive open: PdfReader.source / PdfEditorView.source paint
// page one from a sparse first-paint open, then swap the full buffer in behind
// a background read. Also covers the public readSourceFully helper and the
// PdfProgressiveSourceBuilder it composes.

import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A range-serving in-memory source that records its reads and can gate them
/// behind a [Completer], so a test can hold the background full read open while
/// asserting that the first paint already happened.
class _RecordingSource implements PdfByteSource {
  _RecordingSource(this._bytes, {this.reportLength = true});

  final Uint8List _bytes;
  final bool reportLength;
  final List<(int, int)> reads = [];
  int closeCount = 0;

  /// When set, every [readRange] awaits this before answering. Used to freeze
  /// the background read mid-flight.
  Completer<void>? gate;

  @override
  Future<int?> get length async => reportLength ? _bytes.length : null;

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    reads.add((start, endExclusive));
    final g = gate;
    if (g != null) await g.future;
    final s = start < 0 ? 0 : (start > _bytes.length ? _bytes.length : start);
    final e = endExclusive < s
        ? s
        : (endExclusive > _bytes.length ? _bytes.length : endExclusive);
    return Uint8List.sublistView(_bytes, s, e);
  }

  @override
  Future<void> close() async => closeCount++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pump();
  }

  group('readSourceFully', () {
    test('reassembles the exact file with progress (known length)', () async {
      final bytes = buildMultiPagePdf(3);
      final source = _RecordingSource(bytes);
      final events = <(int, int?)>[];
      final full = await readSourceFully(source,
          chunk: 64, onProgress: (r, t) => events.add((r, t)));
      expect(full, bytes);
      expect(events.last, (bytes.length, bytes.length));
    });

    test('reassembles over an unknown-length source with progress', () async {
      final bytes = buildMultiPagePdf(2);
      final source = _RecordingSource(bytes, reportLength: false);
      final events = <(int, int?)>[];
      final full = await readSourceFully(source,
          chunk: 50, onProgress: (r, t) => events.add((r, t)));
      expect(full, bytes);
      // Unknown length: total stays null, received climbs to the full size.
      expect(events.last, (bytes.length, null));
    });

    test('a fired cancel token aborts before reading', () async {
      final source = _RecordingSource(buildMultiPagePdf(2));
      final token = PdfCancelToken()..cancel();
      await expectLater(
        readSourceFully(source, cancelToken: token),
        throwsA(isA<PdfHttpCancelledException>()),
      );
    });
  });

  group('PdfReader.source', () {
    testWidgets('paints from first paint before the full read completes',
        (tester) async {
      final source = _RecordingSource(buildMultiPagePdf(3));
      final order = <String>[];
      await pump(
        tester,
        PdfReader.source(
          source,
          documentId: 'doc-1',
          onFirstPaint: () => order.add('first-paint'),
          onProgress: (received, total) {
            if (total != null && received == total) order.add('full-done');
          },
        ),
      );
      await tester.pumpAndSettle();

      // First paint fired before the background read reached the full length -
      // ordering proves page one was live before the file finished loading.
      expect(order, ['first-paint', 'full-done']);
      // The inner byte-based reader (and its viewer) mounted in place.
      expect(find.byType(PdfViewer), findsOneWidget);
      // The host-owned source is never closed by the widget.
      expect(source.closeCount, 0);
    });

    testWidgets('shows a loader until the first paint, then the viewer',
        (tester) async {
      final source = _RecordingSource(buildMultiPagePdf(2));
      source.gate = Completer<void>();
      await pump(
        tester,
        PdfReader.source(source, documentId: 'doc-2'),
      );
      // Reads are gated: nothing has painted yet.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(PdfViewer), findsNothing);

      // Release the gate and let the open complete.
      source.gate!.complete();
      source.gate = null;
      await tester.pumpAndSettle();
      expect(find.byType(PdfViewer), findsOneWidget);
    });

    testWidgets('cancels the in-flight read on dispose', (tester) async {
      final source = _RecordingSource(buildMultiPagePdf(2));
      source.gate = Completer<void>();
      await pump(tester, PdfReader.source(source, documentId: 'doc-3'));
      await tester.pump();

      // Dispose while the first read is still gated; disposing must not throw
      // and the pending read is cancelled cooperatively.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      source.gate!.complete();
      await tester.pumpAndSettle();
      // No exception surfaced from the abandoned load.
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens an unknown-length source (sequential fallback)',
        (tester) async {
      // No length -> openSource can't serve ranges and falls back to a plain
      // sequential download internally, still yielding a renderable document.
      // The widget must open and paint it just the same.
      final source = _RecordingSource(buildMultiPagePdf(2), reportLength: false);
      await pump(tester, PdfReader.source(source, documentId: 'doc-4'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PdfEditorView.source', () {
    testWidgets('gates the editing toolbar until the full read completes',
        (tester) async {
      final source = _RecordingSource(buildMultiPagePdf(3));
      // Freeze the background full read the moment the first paint lands, so we
      // can observe the gated (preview) state before the swap.
      await pump(
        tester,
        PdfEditorView.source(
          source,
          documentId: 'edit-1',
          onFirstPaint: () => source.gate = Completer<void>(),
        ),
      );
      // First paint is up but the full read is held: page shows, toolbar gated.
      await tester.pump();
      await tester.pump();
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.byType(PdfEditingToolbar), findsNothing);

      // Release the full read: the buffer swaps and editing comes alive.
      source.gate!.complete();
      source.gate = null;
      await tester.pumpAndSettle();
      expect(find.byType(PdfEditingToolbar), findsOneWidget);
    });
  });

  group('PdfProgressiveSourceBuilder', () {
    testWidgets('uses a custom loadingBuilder before any bytes land',
        (tester) async {
      final source = _RecordingSource(buildMultiPagePdf(1));
      source.gate = Completer<void>();
      await pump(
        tester,
        PdfProgressiveSourceBuilder(
          source: source,
          loadingBuilder: (_) => const Text('loading-pdf'),
          builder: (_, __, ___) => const Text('viewer'),
        ),
      );
      await tester.pump();
      expect(find.text('loading-pdf'), findsOneWidget);
      source.gate!.complete();
      source.gate = null;
      await tester.pumpAndSettle();
      expect(find.text('viewer'), findsOneWidget);
    });

    testWidgets('surfaces an errorBuilder when the open fails outright',
        (tester) async {
      final source = _ThrowingSource(24);
      await pump(
        tester,
        PdfProgressiveSourceBuilder(
          source: source,
          errorBuilder: (_, error) => Text('failed: $error'),
          builder: (_, __, ___) => const Text('viewer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('failed:'), findsOneWidget);
      expect(find.text('viewer'), findsNothing);
    });

    testWidgets('shows the default error UI when no errorBuilder is given',
        (tester) async {
      await pump(
        tester,
        PdfProgressiveSourceBuilder(
          source: _ThrowingSource(24),
          builder: (_, __, ___) => const Text('viewer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not open document'), findsOneWidget);
    });

    testWidgets('restarts when the source is swapped', (tester) async {
      final first = _RecordingSource(buildMultiPagePdf(2));
      final second = _RecordingSource(buildMultiPagePdf(2));
      final swaps = <int>[];
      Widget host(PdfByteSource source) => PdfProgressiveSourceBuilder(
            source: source,
            builder: (_, bytes, __) {
              swaps.add(bytes.length);
              return const Text('viewer');
            },
          );
      await pump(tester, host(first));
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: host(second))));
      await tester.pumpAndSettle();
      // Both sources drove the builder; the second one was actually read.
      expect(second.reads, isNotEmpty);
      expect(find.text('viewer'), findsOneWidget);
    });
  });
}

/// A source that reports a length but throws on every read, so both the
/// first-paint open and the background full read fail.
class _ThrowingSource implements PdfByteSource {
  _ThrowingSource(this._length);
  final int _length;

  @override
  Future<int?> get length async => _length;

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async =>
      throw StateError('read failed');

  @override
  Future<void> close() async {}
}
