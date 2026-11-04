// The paste priority order and in-app clipboard exclusivity, driven through
// a fake system clipboard - no viewer pumped.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/paste_routing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

final _png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
    'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

class _FakeClipboard implements PdfSystemClipboardPort {
  PdfClipboardPdf? pdf;
  Uint8List? image;
  String? text;
  final reads = <String>[];

  @override
  bool get offersPdf => true;

  @override
  Future<PdfClipboardPdf?> readPdf() async {
    reads.add('pdf');
    return pdf;
  }

  @override
  Future<Uint8List?> readImage() async {
    reads.add('image');
    return image;
  }

  @override
  Future<String?> readText() async {
    reads.add('text');
    return text;
  }
}

void main() {
  late PdfEditingController editing;
  late _FakeClipboard system;

  setUp(() {
    editing = PdfEditingController(buildMultiPagePdf(2),
        snapshotClipboard: PdfSnapshotClipboard(),
        annotationClipboard: PdfAnnotationSnapshotClipboard());
    system = _FakeClipboard();
  });
  tearDown(() => editing.dispose());

  void copyRectangle() {
    editing
      ..addRectangle(0, const PdfRect(100, 650, 250, 750))
      ..selectAnnotationsIn(0, const PdfRect(0, 0, 612, 792))
      ..copySelectedAnnotations();
  }

  Uint8List onePagePdf() => buildMultiPagePdf(1);

  group('in-app clipboard exclusivity', () {
    test('an annotation copy drops the snapshot, and back', () {
      editing.copyVectorSnapshot(0, const PdfRect(0, 0, 200, 200));
      expect(editing.inAppPasteSource, PdfPasteSource.snapshot);
      copyRectangle();
      expect(editing.inAppPasteSource, PdfPasteSource.annotations);
      expect(editing.hasSnapshotClipboard, isFalse);
      editing.copyVectorSnapshot(0, const PdfRect(0, 0, 200, 200));
      expect(editing.inAppPasteSource, PdfPasteSource.snapshot);
      expect(editing.hasAnnotationClipboard, isFalse);
    });

    test('empty clipboards have nothing to offer without a system PDF', () {
      expect(editing.inAppPasteSource, isNull);
      expect(PdfPasteRouter.canOffer(editing), isFalse);
      expect(PdfPasteRouter.canOffer(editing, port: system), isTrue);
    });
  });

  group('priority order', () {
    test('a new system PDF beats the in-app clipboard', () async {
      copyRectangle();
      system.pdf = PdfClipboardPdf(onePagePdf(), changeToken: 1);
      final router = PdfPasteRouter(system);
      expect(await router.paste(editing, 1, null), PdfPasteSource.systemPdf);
      // the same system revision yields to a later in-app copy
      copyRectangle();
      expect(await router.paste(editing, 1, null), PdfPasteSource.annotations);
      // a new revision wins again
      system.pdf = PdfClipboardPdf(onePagePdf(), changeToken: 2);
      expect(await router.paste(editing, 1, null), PdfPasteSource.systemPdf);
    });

    test('in-app clipboard beats a system image unless the host overrides',
        () async {
      copyRectangle();
      system.image = _png;
      expect(await PdfPasteRouter(system).paste(editing, 0, (300, 300)),
          PdfPasteSource.annotations);
      expect(system.reads, ['pdf']);
      system.reads.clear();
      expect(
          await PdfPasteRouter(system, systemImageFirst: true)
              .paste(editing, 0, (300, 300)),
          PdfPasteSource.systemImage);
      expect(system.reads, ['pdf', 'image']);
    });

    test('with empty in-app clipboards: image, then text', () async {
      final router = PdfPasteRouter(system);
      system.image = _png;
      system.text = 'hello';
      expect(await router.paste(editing, 0, null), PdfPasteSource.systemImage);
      system.image = null;
      expect(await router.paste(editing, 0, null), PdfPasteSource.systemText);
      expect(editing.pageAt(0).annotations.last.subtype, 'FreeText');
      system.text = '   ';
      expect(await router.paste(editing, 0, null), PdfPasteSource.none);
    });

    test('snapshot pastes ahead of annotations when it is the newer copy',
        () async {
      copyRectangle();
      editing.copyVectorSnapshot(0, const PdfRect(0, 0, 200, 200));
      expect(await PdfPasteRouter(system).paste(editing, 1, null),
          PdfPasteSource.snapshot);
    });
  });

  group('staleness', () {
    test('a paste that loses currency mid-read places nothing', () async {
      copyRectangle();
      final before = editing.revisionId;
      expect(
          await PdfPasteRouter(system)
              .paste(editing, 0, null, stillCurrent: () => false),
          PdfPasteSource.none);
      expect(editing.revisionId, before);
    });

    test('a missing page places nothing', () async {
      system.text = 'hello';
      expect(await PdfPasteRouter(system).paste(editing, 9, null),
          PdfPasteSource.none);
    });
  });
}
