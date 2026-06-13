import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('view sync mirrors scroll position onto the other pane',
      (tester) async {
    final docBytes = buildMultiPagePdf(5);
    final a = PdfViewerController();
    final b = PdfViewerController();
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          Expanded(
            child: PdfViewer(
              document: PdfDocument.open(docBytes),
              controller: a,
              initialFit: PdfViewerFit.width,
            ),
          ),
          Expanded(
            child: PdfViewer(
              document: PdfDocument.open(docBytes),
              controller: b,
              initialFit: PdfViewerFit.width,
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();

    // Jump the first pane to a later page, then mirror it onto the second
    // via the public sync snapshot — the primitive the comparison view's
    // sync link applies on every scroll.
    a.jumpToPage(3);
    await tester.pumpAndSettle();
    expect(a.currentPage, 3);

    b.applyViewSync(a.viewSync!);
    await tester.pumpAndSettle();
    expect(b.currentPage, a.currentPage);
  });

  testWidgets('comparison view lists changes and toggles mode',
      (tester) async {
    final before = _textPdf('the quick brown fox');
    final after = _textPdf('the quick red fox');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfComparisonView(before: before, after: after),
      ),
    ));
    // build() runs after the first frame and notifies the navigator.
    await tester.pump();
    await tester.pump();

    // Both panes mount in side-by-side mode.
    expect(find.byKey(const ValueKey('pdf-compare-before')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-compare-after')), findsOneWidget);

    // The navigator lists the replaced text.
    expect(find.byKey(const ValueKey('pdf-diff-change-0')), findsOneWidget);

    // Switch to overlay mode — one pane only.
    await tester.tap(find.text('Overlay'));
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-compare-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-compare-before')), findsNothing);
  });
}

/// A one-page 612×792 PDF drawing [text] at 72,720 in 18pt Helvetica.
List<int> _bytes(String s) => s.codeUnits;

Uint8List _textPdf(String text) {
  final content = 'BT /F1 18 Tf 72 720 Td ($text) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(_bytes(buffer.toString()));
}
