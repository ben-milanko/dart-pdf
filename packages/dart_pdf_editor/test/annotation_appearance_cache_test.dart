// _AnnotationAppearanceLayer caches rendered appearances by appearance-stream
// identity (#404), so committing one edit no longer re-renders every
// annotation on the page.
//
// The risk caching introduces is lifetime, not reuse: a picture dropped from
// the cache may still be referenced by the list the painter holds, and
// Canvas.drawPicture ASSERTS on a disposed picture. A first cut disposed on
// eviction and broke ~40 existing tests, because a render awaits its missing
// appearances and a frame can paint during that window.
//
// These pump through the transitions that open that window. A
// disposed-picture paint surfaces as an unhandled framework exception, which
// flutter_test fails on by itself, so the pumps carry the real assertion and
// the expects below just pin the document state.
//
// Re-run against the disposing version, the last TWO fail: restyling replaces
// one appearance stream and deleting drops one, so both evict. The first only
// adds annotations, so nothing is ever evicted and it passes either way - it
// is here to cover the plain repeat-commit path, not the lifetime bug.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PdfEditingController> pumpViewer(WidgetTester tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return editing;
  }

  testWidgets('repeated commits on an annotated page keep painting',
      (tester) async {
    final editing = await pumpViewer(tester);
    for (var i = 0; i < 6; i++) {
      editing.addRectangle(
          0, PdfRect(100, 600.0 - i * 20, 250, 640.0 - i * 20));
      await tester.pumpAndSettle();
    }
    expect(editing.document.page(0).annotations, hasLength(6));
  });

  testWidgets('restyling one annotation keeps the other on screen',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing.addRectangle(0, const PdfRect(100, 600, 250, 640));
    editing.addRectangle(0, const PdfRect(300, 600, 450, 640));
    await tester.pumpAndSettle();

    // One appearance stream is replaced; the other is untouched and has to
    // survive out of the cache while the replacement renders.
    expect(editing.selectAnnotation(0, 0), isTrue);
    expect(editing.restyleSelected(color: const Color(0xFF00FF00)), isTrue);
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations, hasLength(2));
  });

  testWidgets('deleting then undoing retires and revives pictures safely',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing.addRectangle(0, const PdfRect(100, 600, 250, 640));
    editing.addRectangle(0, const PdfRect(300, 600, 450, 640));
    await tester.pumpAndSettle();

    expect(editing.selectAnnotation(0, 0), isTrue);
    editing.deleteSelected();
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations, hasLength(1));

    editing.undo();
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations, hasLength(2));
  });
}
