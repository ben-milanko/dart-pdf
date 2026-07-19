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
/// FutureBuilder resolves and the loading spinner disappears, then a few
/// extra frames so the visible pages' lazily-decoded images land.
Future<void> _settle(WidgetTester tester) async {
  var clearedAt = -1;
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      if (clearedAt < 0) clearedAt = i;
      // Give per-page image decoding a handful of frames to complete.
      if (i - clearedAt >= 12) return;
    }
  }
}

/// Pumps a handful of frames so the reflow view's post-frame jump/restore
/// corrections (estimate → build → align) run to completion.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
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

  testWidgets('lazily builds only the pages near the viewport', (tester) async {
    await tester.runAsync(() async {
      // A long document: a non-lazy layout would build every page's
      // SelectableText up front (the old, slow behaviour). The lazy list
      // builds only the pages near the viewport, so a far page is absent.
      final doc = PdfDocument.open(_multiPageDoc([
        for (var i = 0; i < 40; i++) _text(100, 700, 'Text page $i'),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: doc, showImages: false)),
      ));
      await _settle(tester);

      expect(find.text('Text page 0'), findsOneWidget);
      expect(find.text('Text page 39'), findsNothing,
          reason: 'a far page is not built until it scrolls near the viewport');
    });
  });

  testWidgets('a controller jumps the reading view to a page and tracks it',
      (tester) async {
    await tester.runAsync(() async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      final doc = PdfDocument.open(_multiPageDoc([
        for (var i = 0; i < 40; i++) _text(100, 700, 'Text page $i'),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReflowView(
              document: doc, controller: controller, showImages: false),
        ),
      ));
      await _settle(tester);

      // The reading view reports the document's page count to the controller.
      expect(controller.pageCount, 40);

      await controller.jumpToPage(30);
      await _pumpFrames(tester);

      expect(find.text('Text page 30'), findsOneWidget,
          reason: 'jumpToPage scrolls the reading view to the target page');
      expect(controller.currentPage, 30,
          reason: 'the reading view reports its current page back');
    });
  });

  testWidgets('captures and restores the reading position', (tester) async {
    await tester.runAsync(() async {
      final contents = [
        for (var i = 0; i < 40; i++) _text(100, 700, 'Text page $i'),
      ];
      final first = PdfViewerController();
      addTearDown(first.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReflowView(
              document: PdfDocument.open(_multiPageDoc(contents)),
              controller: first,
              showImages: false),
        ),
      ));
      await _settle(tester);

      await first.jumpToPage(20);
      await _pumpFrames(tester);
      final saved = first.captureViewport();
      expect(saved, isNotNull);
      expect(saved!.page, 20);

      // Reopen the document in a fresh reading view and restore the snapshot -
      // the reader lands back on the saved page.
      final second = PdfViewerController();
      addTearDown(second.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReflowView(
              document: PdfDocument.open(_multiPageDoc(contents)),
              controller: second,
              showImages: false),
        ),
      ));
      await _settle(tester);
      second.restoreViewport(saved);
      await _pumpFrames(tester);

      expect(find.text('Text page 20'), findsOneWidget);
    });
  });

  testWidgets('tapping a figure opens it fullscreen with zoom and share',
      (tester) async {
    await tester.runAsync(() async {
      Uint8List? shared;
      final doc = PdfDocument.open(_imagePdf());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReflowView(
            document: doc,
            onShareImage: (context, png) async => shared = png,
          ),
        ),
      ));
      await _settle(tester);
      expect(find.byType(RawImage), findsOneWidget);

      await tester.tap(find.byType(RawImage));
      await tester.pumpAndSettle();

      // The fullscreen viewer is an InteractiveViewer (pan / pinch-zoom).
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final shareButton =
          find.byKey(const ValueKey('pdf-reflow-image-share'));
      expect(shareButton, findsOneWidget);

      await tester.tap(shareButton);
      await _pumpFrames(tester);
      expect(shared, isNotNull, reason: 'the share handler receives PNG bytes');

      await tester.tap(find.byKey(const ValueKey('pdf-reflow-image-close')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });
  });

  testWidgets('the fullscreen figure hides share when no handler is given',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(_imagePdf());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: doc)),
      ));
      await _settle(tester);

      await tester.tap(find.byType(RawImage));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-reflow-image-share')), findsNothing,
          reason: 'no share handler → no share action, viewing still works');
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
