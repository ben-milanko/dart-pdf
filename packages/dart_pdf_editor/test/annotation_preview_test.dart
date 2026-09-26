import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Captures [finder]'s first [PdfAnnotationAppearancePreview] as RGBA bytes.
Future<(int, int, List<int>)> _pixels(
    WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final (width, height, bytes) = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (image.width, image.height, data!.buffer.asUint8List());
    image.dispose();
    return result;
  }))!;
  return (width, height, bytes);
}

/// Whether any pixel is clearly not white paper or the card's grey border.
bool _hasInk(List<int> rgba, int width, int height) {
  for (var y = 3; y < height - 3; y++) {
    for (var x = 3; x < width - 3; x++) {
      final i = (y * width + x) * 4;
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      if ((r - g).abs() > 60 || (r - b).abs() > 60 || r < 128) return true;
    }
  }
  return false;
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    // the appearance renders through real async image decoding
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  testWidgets('the annotation list shows each annotation\'s appearance',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(100, 650, 250, 750));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body:
            PdfAnnotationSidebar(controller: editing, viewerController: viewer),
      ),
    ));
    await settle(tester);

    final preview = find.byKey(const ValueKey('pdf-annotation-preview-0-0'));
    expect(preview, findsOneWidget);
    expect(
        find.descendant(of: preview, matching: find.byType(Icon)), findsNothing,
        reason: 'the rendered appearance replaces the subtype icon');
    final card =
        find.descendant(of: preview, matching: find.byType(RepaintBoundary));
    final (w, h, rgba) = await _pixels(tester, card.first);
    // the card is white paper even in a dark theme (the square is unfilled)
    final center = ((h ~/ 2) * w + w ~/ 2) * 4;
    expect(rgba.sublist(center, center + 3), [255, 255, 255]);
    expect(_hasInk(rgba, w, h), isTrue,
        reason: 'the square\'s stroke is drawn in the card');
  });

  testWidgets('an annotation without an appearance keeps its icon',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    // a bare /Link with no /AP
    final page = editing.pageAt(0);
    final link = PdfAnnotation.fromDict(
      page.document,
      CosDictionary({
        'Type': const CosName('Annot'),
        'Subtype': const CosName('Link'),
        'Rect': CosArray([
          for (final v in [10, 10, 60, 30]) CosInteger(v),
        ]),
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfAnnotationAppearancePreview(
          page: page,
          annotation: link,
          icon: Icons.link,
        ),
      ),
    ));
    await settle(tester);
    expect(find.byIcon(Icons.link), findsOneWidget);
  });

  testWidgets('the annotation library shows the saved appearance',
      (tester) async {
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )..addRectangle(0, const PdfRect(100, 650, 250, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    editing.saveSelectedAnnotation('Reusable box');
    editing.deleteSelected();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfAnnotationLibraryPanel(controller: editing),
      ),
    ));
    await settle(tester);

    final preview = find.byType(PdfAnnotationAppearancePreview);
    expect(preview, findsOneWidget);
    expect(find.descendant(of: preview, matching: find.byType(Icon)),
        findsNothing);
    final card =
        find.descendant(of: preview, matching: find.byType(RepaintBoundary));
    final (w, h, rgba) = await _pixels(tester, card.first);
    expect(_hasInk(rgba, w, h), isTrue);
  });
}
