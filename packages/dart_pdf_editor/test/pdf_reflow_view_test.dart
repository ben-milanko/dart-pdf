import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Uint8List _assemble(List<String> objects) {
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
  return ascii(buffer.toString());
}

/// A one-page PDF whose content is [content]; an `/Im0` image XObject (its
/// stream body is [imageHex] decoded as ASCII-hex) and an `/F1` Helvetica
/// font are available as resources.
Uint8List _doc(String content,
    {String imageHex = 'FF000000FF000000FFFFFFFF>'}) {
  return _assemble([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> /XObject << /Im0 6 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /XObject /Subtype /Image /Width 2 /Height 2 '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode '
        '/Length ${imageHex.length} >>\nstream\n$imageHex\nendstream',
  ]);
}

/// A multi-page PDF; every page shares the `/F1` font and `/Im0` image
/// resources, with [contents] supplying each page's content stream.
Uint8List _multiPageDoc(List<String> contents) {
  const hex = 'FF000000FF000000FFFFFFFF>';
  final n = contents.length;
  final fontObj = 3 + 2 * n;
  final imageObj = 4 + 2 * n;
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[
      for (var i = 0; i < n; i++) '${3 + 2 * i} 0 R'
    ].join(' ')}] /Count $n >>',
  ];
  for (var i = 0; i < n; i++) {
    final contentObj = 4 + 2 * i;
    objects
      ..add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Contents $contentObj 0 R /Resources << /Font << /F1 $fontObj 0 R >> '
          '/XObject << /Im0 $imageObj 0 R >> >> >>')
      ..add('<< /Length ${contents[i].length} >>\n'
          'stream\n${contents[i]}\nendstream');
  }
  objects
    ..add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
    ..add('<< /Type /XObject /Subtype /Image /Width 2 /Height 2 '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode '
        '/Length ${hex.length} >>\nstream\n$hex\nendstream');
  return _assemble(objects);
}

String _text(num x, num y, String text, {int size = 12}) =>
    'BT /F1 $size Tf $x $y Td ($text) Tj ET';

const _imageContent = 'q 200 0 0 120 100 480 cm /Im0 Do Q';

Uint8List _imagePdf() => _doc('${_text(100, 700, 'Above the figure')}\n'
    '$_imageContent\n'
    '${_text(100, 360, 'Below the figure')}');

/// Pumps frames (driving real async for image decoding) until the
/// FutureBuilder resolves and the loading spinner disappears.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

void main() {
  testWidgets('renders a placed image inline with the text', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(_imagePdf());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: doc)),
      ));
      await _settle(tester);

      expect(find.text('Above the figure'), findsOneWidget);
      expect(find.text('Below the figure'), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
    });
  });

  testWidgets('showImages: false reads text-only, no image', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(_imagePdf());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReflowView(document: doc, showImages: false),
        ),
      ));
      await _settle(tester);

      expect(find.text('Above the figure'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    });
  });

  testWidgets('styles a heading and indents a list item', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(_doc('${_text(100, 720, 'Big Heading', size: 24)}\n'
          '${_text(100, 680, '- first item')}\n'
          '${_text(100, 664, '- second item')}'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: doc)),
      ));
      await _settle(tester);

      expect(find.text('Big Heading'), findsOneWidget);
      // The list items render and hang under a left-indent Padding.
      expect(find.text('- first item'), findsOneWidget);
      final indented = tester.widgetList<Padding>(find.ancestor(
        of: find.text('- first item'),
        matching: find.byType(Padding),
      ));
      expect(
        indented.any((p) =>
            p.padding.resolve(TextDirection.ltr).left == 16),
        isTrue,
      );
    });
  });

  testWidgets('falls back to a placeholder for an undecodable image',
      (tester) async {
    await tester.runAsync(() async {
      // The image declares 2x2 RGB (12 bytes) but provides one byte: decode
      // fails, so the view surfaces a labelled placeholder instead.
      final doc = PdfDocument.open(_doc(_imageContent, imageHex: '00>'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: doc)),
      ));
      await _settle(tester);

      expect(find.byType(RawImage), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });
  });

  testWidgets('shows a message when there is no extractable content',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(_doc('')); // blank page
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: doc)),
      ));
      await _settle(tester);

      expect(find.text('No extractable content'), findsOneWidget);
    });
  });

  testWidgets('scroll extent stays stable across scrolling', (tester) async {
    await tester.runAsync(() async {
      // Alternate tall image pages with short text pages: a lazy ListView's
      // extent estimate would drift as the differing heights build, jumping
      // the scrollbar. The non-lazy scroll keeps it exact.
      final doc = PdfDocument.open(_multiPageDoc([
        for (var i = 0; i < 6; i++)
          i.isEven
              ? '$_imageContent\n${_text(100, 440, 'Image page $i')}'
              : _text(100, 700, 'Text page $i'),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: doc)),
      ));
      await _settle(tester);

      // The outer scroll view's Scrollable is the first descendant of the
      // keyed widget (the SelectableTexts add their own deeper ones).
      final position = tester
          .state<ScrollableState>(find
              .descendant(
                of: find.byKey(const ValueKey('pdf-reflow-view')),
                matching: find.byType(Scrollable),
              )
              .first)
          .position;
      final before = position.maxScrollExtent;
      expect(before, greaterThan(0));

      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      // Exact extent: jumping to the end does not revise it.
      expect(position.maxScrollExtent, before);
    });
  });

  testWidgets('reloads when the document changes', (tester) async {
    await tester.runAsync(() async {
      final first = PdfDocument.open(_imagePdf());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: first)),
      ));
      await _settle(tester);
      expect(find.text('Above the figure'), findsOneWidget);

      final second = PdfDocument.open(_doc(_text(100, 700, 'A different page')));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: second)),
      ));
      await _settle(tester);

      expect(find.text('Above the figure'), findsNothing);
      expect(find.text('A different page'), findsOneWidget);
    });
  });
}
