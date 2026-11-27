import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

Uint8List _widePdf() {
  final marks = StringBuffer('0.2 0.4 0.6 RG 0.6 w\n');
  for (var i = 0; i < 8400; i++) {
    final x = i * 37 % 2360;
    final y = i * 19 % 570;
    marks.writeln('$x $y m ${x + 25} ${y + 7} l S');
  }
  final ink = marks.toString();
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 3 /Kids [5 0 R 3 0 R 6 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 2400 600] '
        '/Resources << >> /Contents 4 0 R >>',
    '<< /Length ${ink.length} >>\nstream\n${ink}endstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 840 594] /Resources << >> >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 840 594] /Resources << >> >>',
  ];
  var result = '%PDF-1.4\n';
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(result.length);
    result += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final xref = result.length;
  result += 'xref\n0 7\n0000000000 65535 f \n';
  for (final offset in offsets) {
    result += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  result += 'trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
  return Uint8List.fromList(ascii.encode(result));
}

Rect _asRect(Object? value) {
  final v = (value as List).cast<num>();
  return Rect.fromLTRB(
    v[0].toDouble(),
    v[1].toDouble(),
    v[2].toDouble(),
    v[3].toDouble(),
  );
}

void main() {
  testWidgets('tile demand follows actual viewer constraints at zoom and pan', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = PdfViewerController();
    final store = PdfTileStore(registerForMemoryPressure: false);
    final original = PdfPageView.debugTileStoreOverride;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.debugTileStoreOverride = original;
      store.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 500,
              child: PdfViewer(
                document: PdfDocument.open(_widePdf()),
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
    }

    await settle();
    controller.setZoom(3);
    final jump = controller.jumpToPage(1);
    await settle();
    await jump;
    Future<Rect> check(String phase) async {
      await settle();
      final page = PdfPageViewDiagnostics.instance
          .snapshot()
          .singleWhere((p) => p['pageIndex'] == 1);
      final tiles = (page['tiles'] as Map).cast<String, Object?>();
      expect(tiles['pathStatus'], 'active', reason: phase);
      expect(tiles['layerMounted'], true, reason: '$phase: ${page['detail']}');
      final actual = controller.visiblePageRegion(1)!;
      final demanded = _asRect(tiles['fraction']);
      final coverage = ((tiles['coverage'] as Map)['tileFraction'] as Map);
      expect(coverage['missing'], 0, reason: phase);
      expect(coverage['visible'], greaterThan(0), reason: phase);
      expect(demanded.left, closeTo(actual.left, 0.001), reason: phase);
      expect(demanded.top, closeTo(actual.top, 0.001), reason: phase);
      expect(demanded.right, closeTo(actual.right, 0.001), reason: phase);
      expect(demanded.bottom, closeTo(actual.bottom, 0.001), reason: phase);
      return actual;
    }

    final beforePan = await check('zoom');
    final pan = controller.revealRect(1, const PdfRect(1700, 280, 1740, 320));
    await settle();
    await pan;
    final afterPan = await check('pan');
    expect(afterPan.left, isNot(closeTo(beforePan.left, 0.001)));
    controller.rotateView(90);
    await settle();
    controller.setZoom(3);
    final rotatedJump = controller.jumpToPage(1);
    await settle();
    await rotatedJump;
    await check('rotated');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
