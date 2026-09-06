import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final diagnostics = PdfTileRasterDiagnostics.instance;

  setUp(() async {
    pdfDebugShowGpuRasterRoutes.value = false;
    diagnostics.clear();
    await pumpEventQueue();
  });

  tearDown(() async {
    pdfDebugShowGpuRasterRoutes.value = false;
    diagnostics.clear();
    await pumpEventQueue();
  });

  testWidgets('GPU route devtool follows the live page route', (tester) async {
    final namespace = Object();
    pdfDebugShowGpuRasterRoutes.value = true;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 612,
          height: 792,
          child: PdfGpuRasterRouteOverlay(
            cacheNamespace: namespace,
            pageIndex: 0,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pdf-gpu-route-overlay')), findsOneWidget);
    expect(find.text('Detail tiles: not active'), findsOneWidget);
    expect(find.text('Fitted page: Canvas'), findsOneWidget);

    diagnostics.reportSession(
      cacheNamespace: namespace,
      document: Object(),
      scene: Object(),
      pageIndex: 0,
      requestedBackend: 'flutter_gpu',
      effectiveBackend: 'flutter_gpu',
      commandCount: 28,
      pageColor: 0xFFFFFFFF,
      annotations: true,
      rotation: null,
    );
    diagnostics.reportTile(
      cacheNamespace: namespace,
      pageIndex: 0,
      region: const Rect.fromLTWH(0, 0, 100, 100),
      pixelRatio: 2,
      width: 200,
      height: 200,
    );
    await tester.pump();

    expect(find.text('Detail tiles: GPU · flutter_gpu'), findsOneWidget);
    expect(find.text('1 tile · 28 commands'), findsOneWidget);

    diagnostics.reportFallback(
      cacheNamespace: namespace,
      pageIndex: 0,
      error: StateError('device lost'),
    );
    await tester.idle();
    await tester.pump();

    expect(find.text('Detail tiles: Canvas fallback'), findsOneWidget);
    expect(find.textContaining('device lost'), findsOneWidget);

    pdfDebugShowGpuRasterRoutes.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-gpu-route-overlay')), findsNothing);
  });

  testWidgets('GPU route badge stays screen-sized under viewer zoom',
      (tester) async {
    final zoom = ValueNotifier<double>(4);
    addTearDown(zoom.dispose);
    pdfDebugShowGpuRasterRoutes.value = true;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 612,
          height: 792,
          child: PdfGpuRasterRouteOverlay(
            cacheNamespace: Object(),
            pageIndex: 0,
            transformScale: zoom,
          ),
        ),
      ),
    );

    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(const ValueKey('pdf-gpu-route-overlay')),
        matching: find.byType(Transform),
      ),
    );
    expect(transform.transform.storage[0], closeTo(0.25, 0.0001));

    zoom.value = 2;
    await tester.pump();
    final updated = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(const ValueKey('pdf-gpu-route-overlay')),
        matching: find.byType(Transform),
      ),
    );
    expect(updated.transform.storage[0], closeTo(0.5, 0.0001));
  });
}
