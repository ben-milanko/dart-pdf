// Tool gestures without a widget: what the mode answers the viewer asks,
// which drag each tool's behaviour declares, and what its region and tap
// commits do through a recording PdfToolHost.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_tool_behavior.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Records what a tool asked of its page; maps view to page 1:1 (y down).
class _Host implements PdfToolHost {
  _Host(this.controller);

  @override
  final PdfEditingController controller;

  final calls = <String>[];
  String? noteText = 'A note';
  String? stampText = 'OK';

  @override
  int get page => 0;

  @override
  (double, double) toPagePoint(Offset view) => (view.dx, 792 - view.dy);

  @override
  PdfRect toPageRect(Rect view) =>
      PdfRect(view.left, 792 - view.bottom, view.right, 792 - view.top);

  @override
  void openTextBox(Rect box) => calls.add('textBox $box');
  @override
  void openCallout(Rect box, Offset terminus) =>
      calls.add('callout $box -> $terminus');
  @override
  void openCloudCallout(Rect region) => calls.add('cloud $region');
  @override
  Rect defaultBoxAt(Offset at) => at & const Size(200, 30);
  @override
  Rect defaultCloudAt(Offset center) =>
      Rect.fromCenter(center: center, width: 120, height: 72);
  @override
  Rect calloutBoxFor(Offset start, Offset end) => end & const Size(200, 30);

  @override
  Future<String?> promptNoteText() async => noteText;
  @override
  Future<String?> promptStampText() async => stampText;
  @override
  Future<void> calibrate(Offset start, Offset end) async =>
      calls.add('calibrate');
  @override
  Future<void> measureCustom(Offset start, Offset end) async =>
      calls.add('measureCustom');
  @override
  Future<void> addImageIn(PdfRect rect) async => calls.add('imageIn');
  @override
  Future<void> placeImageAt(double x, double y) async =>
      calls.add('imageAt ($x, $y)');
  @override
  Future<void> addLinkIn(PdfRect rect) async => calls.add('linkIn');
  @override
  Future<void> placeSignatureBox(PdfRect rect) async =>
      calls.add('signatureBox');
  @override
  Future<void> snapshot(Rect box, PdfRect rect) async => calls.add('snapshot');
  @override
  void placeSignatureAt(Offset at) => calls.add('signatureAt $at');

  @override
  void holdShape(PdfEditTool tool, Rect box, int before) =>
      calls.add('holdShape ${tool.name} ${before != controller.revisionId}');
  @override
  void holdLine(PdfEditTool tool, Offset start, Offset end, int before) =>
      calls.add('holdLine ${tool.name} ${before != controller.revisionId}');
  @override
  void holdCheckMark(int before) =>
      calls.add('holdCheckMark ${before != controller.revisionId}');
  @override
  Future<void> stampBox(Rect box,
      {required String? text,
      PdfStampTemplate? template,
      required Color color,
      required void Function() run}) async {
    calls.add('stampBox $text');
    run();
  }

  @override
  Future<void> stampAt(Offset at,
      {String? text, required void Function() run}) async {
    calls.add('stampAt $text');
    run();
  }
}

PdfToolTap _tap(double x, double y, {bool additive = false}) => (
      at: Offset(x, y),
      point: (x, 792 - y),
      hit: (x, 792 - y),
      additive: additive,
    );

PdfEditToolBehavior _of(PdfEditTool tool) => PdfEditToolBehavior.of(tool);

void main() {
  group('the mode answers the viewer asks', () {
    test('reading modes leave the page to the reader', () {
      for (final mode in const <PdfEditingMode>[
        PdfReaderMode(),
        PdfHandMode(),
        PdfMarkupMode(PdfMarkupKind.highlight),
        PdfSavedAnnotationMode('id'),
        PdfToolMode(PdfEditTool.select),
      ]) {
        expect(mode.armsPageTool, isFalse, reason: '$mode');
        expect(mode.picksFormWidgets, isTrue, reason: '$mode');
        expect(mode.drawsFreehand, isFalse, reason: '$mode');
      }
      expect(const PdfToolMode(PdfEditTool.select).armsSelect, isTrue);
      expect(const PdfReaderMode().armsSelect, isFalse);
    });

    test('page tools own the page; form authoring still picks widgets', () {
      expect(const PdfToolMode(PdfEditTool.rectangle).armsPageTool, isTrue);
      expect(
          const PdfToolMode(PdfEditTool.rectangle).picksFormWidgets, isFalse);
      const form = PdfToolMode(PdfEditTool.form);
      expect((form.armsPageTool, form.authorsForms, form.picksFormWidgets),
          (true, true, true));
    });

    test('freehand is ink, the highlighter and the eraser', () {
      expect({
        for (final tool in PdfEditTool.values)
          if (PdfToolMode(tool).drawsFreehand) tool
      }, {
        PdfEditTool.ink,
        PdfEditTool.highlight,
        PdfEditTool.eraser
      });
    });

    test('only the signature box backs out first on Escape', () {
      expect({
        for (final tool in PdfEditTool.values)
          if (PdfToolMode(tool).escapesFirst) tool
      }, {
        PdfEditTool.signatureBox
      });
    });
  });

  test('each tool declares the drag it starts', () {
    final byDrag = <PdfToolDrag, Set<PdfEditTool>>{};
    for (final tool in PdfEditTool.values) {
      byDrag.putIfAbsent(_of(tool).drag, () => {}).add(tool);
    }
    expect(byDrag[PdfToolDrag.select], {PdfEditTool.select});
    expect(byDrag[PdfToolDrag.erase], {PdfEditTool.eraser});
    expect(
        byDrag[PdfToolDrag.freehand], {PdfEditTool.ink, PdfEditTool.highlight});
    expect(byDrag[PdfToolDrag.form], {PdfEditTool.form});
    expect(byDrag[PdfToolDrag.signature], {PdfEditTool.signature});
    expect(byDrag[PdfToolDrag.content], {PdfEditTool.content});
    expect(byDrag[PdfToolDrag.none], {
      PdfEditTool.polyline,
      PdfEditTool.polygon,
      PdfEditTool.measurePerimeter,
      PdfEditTool.measureArea,
      PdfEditTool.measureAngle,
      PdfEditTool.measureArc,
      PdfEditTool.measureVolume,
      PdfEditTool.note,
      PdfEditTool.count,
    });
    // everything else drags out a region; every line-drag tool does
    for (final tool in PdfEditTool.values) {
      if (_of(tool).isLineDrag) {
        expect(_of(tool).drag, PdfToolDrag.region, reason: tool.name);
      }
    }
  });

  group('region commits', () {
    late PdfEditingController editing;
    late _Host host;
    setUp(() {
      editing = PdfEditingController(buildMultiPagePdf(1));
      host = _Host(editing);
    });

    test('a shape adds its annotation and holds the drag preview', () async {
      await _of(PdfEditTool.rectangle)
          .commitRegion(host, const Offset(100, 100), const Offset(200, 160));
      expect(editing.document.page(0).annotations.single.subtype, 'Square');
      expect(host.calls, ['holdShape rectangle true']);
    });

    test('a click-sized box places nothing', () async {
      for (final tool in [
        PdfEditTool.rectangle,
        PdfEditTool.freeText,
        PdfEditTool.stamp,
        PdfEditTool.redact,
        PdfEditTool.link,
      ]) {
        await _of(tool)
            .commitRegion(host, const Offset(100, 100), const Offset(102, 140));
      }
      expect(host.calls, isEmpty);
      expect(editing.document.page(0).annotations, isEmpty);
    });

    test('a line drag commits the segment; a click does not', () async {
      await _of(PdfEditTool.line)
          .commitRegion(host, const Offset(100, 100), const Offset(102, 101));
      expect(host.calls, isEmpty);
      await _of(PdfEditTool.arrow)
          .commitRegion(host, const Offset(100, 100), const Offset(200, 150));
      expect(editing.document.page(0).annotations.single.subtype, 'Line');
      expect(host.calls, ['holdLine arrow true']);
    });

    test('text tools open the inline editor where the drag aimed', () async {
      await _of(PdfEditTool.freeText)
          .commitRegion(host, const Offset(10, 20), const Offset(110, 60));
      await _of(PdfEditTool.callout)
          .commitRegion(host, const Offset(10, 20), const Offset(110, 60));
      await _of(PdfEditTool.cloudCallout)
          .commitRegion(host, const Offset(10, 20), const Offset(12, 21));
      expect(host.calls, [
        'textBox ${const Rect.fromLTRB(10, 20, 110, 60)}',
        'callout ${const Offset(110, 60) & const Size(200, 30)} -> '
            '${const Offset(10, 20)}',
        'cloud ${Rect.fromCenter(center: const Offset(10, 20), width: 120, height: 72)}',
      ]);
    });

    test('prompt-driven tools hand their flow to the host', () async {
      const a = Offset(100, 100), b = Offset(200, 160);
      await _of(PdfEditTool.calibrate).commitRegion(host, a, b);
      await _of(PdfEditTool.measureCustom).commitRegion(host, a, b);
      await _of(PdfEditTool.image).commitRegion(host, a, b);
      await _of(PdfEditTool.link).commitRegion(host, a, b);
      await _of(PdfEditTool.signatureBox).commitRegion(host, a, b);
      await _of(PdfEditTool.snapshot).commitRegion(host, a, b);
      expect(host.calls, [
        'calibrate',
        'measureCustom',
        'imageIn',
        'linkIn',
        'signatureBox',
        'snapshot',
      ]);
    });

    test('a stamp box prompts for its caption, then stamps', () async {
      await _of(PdfEditTool.stamp)
          .commitRegion(host, const Offset(100, 100), const Offset(220, 150));
      expect(host.calls, ['stampBox OK']);
      expect(editing.document.page(0).annotations.single.subtype, 'Stamp');
      host.stampText = null;
      await _of(PdfEditTool.stamp)
          .commitRegion(host, const Offset(100, 200), const Offset(220, 250));
      expect(host.calls, ['stampBox OK'], reason: 'cancelled: nothing');
    });
  });

  group('tap commits', () {
    late PdfEditingController editing;
    late _Host host;
    setUp(() {
      editing = PdfEditingController(buildMultiPagePdf(1));
      host = _Host(editing);
    });

    test('a note prompts, then lands at the tap', () async {
      await _of(PdfEditTool.note).commitTap(host, _tap(100, 92));
      final note = editing.document.page(0).annotations.single;
      expect(note.subtype, 'Text');
      expect(note.contents, 'A note');
      host.noteText = '';
      await _of(PdfEditTool.note).commitTap(host, _tap(200, 92));
      expect(editing.document.page(0).annotations, hasLength(1));
    });

    test('a count tap drops a check-mark and holds it', () async {
      await _of(PdfEditTool.count).commitTap(host, _tap(100, 100));
      expect(host.calls, ['holdCheckMark true']);
    });

    test('text tools open a default box at the tap', () async {
      await _of(PdfEditTool.freeText).commitTap(host, _tap(10, 20));
      await _of(PdfEditTool.callout).commitTap(host, _tap(10, 20));
      expect(host.calls, [
        'textBox ${const Offset(10, 20) & const Size(200, 30)}',
        'callout ${const Offset(38, -8) & const Size(200, 30)} -> '
            '${const Offset(10, 20)}',
      ]);
    });

    test('tap-created tools are the ones that create on a tap', () {
      expect({
        for (final tool in PdfEditTool.values)
          if (_of(tool).tapCreates) tool
      }, {
        PdfEditTool.note,
        PdfEditTool.count,
        PdfEditTool.signature,
        PdfEditTool.freeText,
        PdfEditTool.callout,
        PdfEditTool.cloudCallout,
        PdfEditTool.stamp,
        PdfEditTool.image,
      });
    });

    test('a stamp tap without an active stamp prompts for a caption', () async {
      await _of(PdfEditTool.stamp).commitTap(host, _tap(100, 100));
      expect(host.calls, ['stampAt OK']);
      expect(editing.document.page(0).annotations.single.subtype, 'Stamp');
    });

    test('drag-only tools ignore a tap', () async {
      for (final tool in [
        PdfEditTool.rectangle,
        PdfEditTool.line,
        PdfEditTool.redact,
        PdfEditTool.select,
      ]) {
        await _of(tool).commitTap(host, _tap(100, 100));
      }
      expect(host.calls, isEmpty);
      expect(editing.document.page(0).annotations, isEmpty);
    });
  });
}
