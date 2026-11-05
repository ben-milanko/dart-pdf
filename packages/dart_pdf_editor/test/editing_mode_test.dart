// Editing-mode transitions as plain controller tests: one value, one
// transition point, its exit/entry work done once.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PdfEditingController editing;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    editing = PdfEditingController(buildMultiPagePdf(1));
  });
  tearDown(() => editing.dispose());

  test('exactly one mode at a time', () {
    expect(editing.mode, const PdfReaderMode());
    editing.tool = PdfEditTool.rectangle;
    expect(editing.mode, const PdfToolMode(PdfEditTool.rectangle));
    editing.markupTool = PdfMarkupKind.highlight;
    expect(editing.mode, const PdfMarkupMode(PdfMarkupKind.highlight));
    expect(editing.tool, isNull);
    editing.activateHandMode();
    expect(editing.mode, const PdfHandMode());
    expect(editing.markupTool, isNull);
    editing.tool = PdfEditTool.select;
    expect(editing.isHandMode, isFalse);
  });

  test('re-entering the current mode does nothing', () {
    editing.tool = PdfEditTool.ink;
    var notified = 0;
    editing.addListener(() => notified++);
    editing.tool = PdfEditTool.ink;
    editing.activateHandMode();
    editing.activateHandMode();
    expect(notified, 1);
  });

  test('leaving ink commits the pending stroke', () {
    editing.tool = PdfEditTool.ink;
    editing.addInkStroke(0, [(10, 10), (40, 40)]);
    expect(editing.hasPendingInk, isTrue);
    editing.activateHandMode();
    expect(editing.hasPendingInk, isFalse);
    expect(editing.document.page(0).annotations.single.subtype, 'Ink');
  });

  test('arming the eraser defers the ink commit a turn', () async {
    editing.tool = PdfEditTool.ink;
    editing.addInkStroke(0, [(10, 10), (40, 40)]);
    editing.tool = PdfEditTool.eraser;
    expect(editing.tool, PdfEditTool.eraser, reason: 'armed at once');
    expect(editing.hasPendingInk, isTrue, reason: 'commit still deferred');
    await Future<void>.delayed(Duration.zero);
    expect(editing.hasPendingInk, isFalse);
    expect(editing.document.page(0).annotations, hasLength(1));
  });

  test('a mode that cannot act on the selection drops it', () {
    editing
      ..addRectangle(0, const PdfRect(100, 100, 200, 200))
      ..tool = PdfEditTool.select
      ..selectAnnotationsIn(0, const PdfRect(0, 0, 612, 792));
    expect(editing.hasAnnotationSelection, isTrue);
    expect(editing.selectsAnnotations, isTrue);
    editing.tool = PdfEditTool.select;
    expect(editing.hasAnnotationSelection, isTrue);
    editing.tool = PdfEditTool.ellipse;
    expect(editing.hasAnnotationSelection, isFalse);
  });

  test('page overlays and editing gestures follow the mode', () {
    expect(editing.wantsPageOverlays, isFalse);
    expect(editing.acceptsEditingGestures, isFalse);
    editing.markupTool = PdfMarkupKind.underline;
    expect(editing.acceptsEditingGestures, isFalse,
        reason: 'markup rides the viewer selection gestures');
    editing.tool = PdfEditTool.freeText;
    expect(editing.wantsPageOverlays, isTrue);
    expect(editing.acceptsEditingGestures, isTrue);
    editing.tool = null;
    editing.startColorPick();
    expect(editing.wantsPageOverlays, isTrue);
    expect(editing.acceptsEditingGestures, isFalse);
  });
}
