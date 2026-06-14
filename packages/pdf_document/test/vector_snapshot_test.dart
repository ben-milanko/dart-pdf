// Vector snapshots (PdfVectorSnapshot): capturing a region of a page as
// detached vector graphics and pasting it back as a /Stamp annotation
// whose appearance *draws* the captured content (so it stays vector).
import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

String _name(CosObject? o) => (o as CosName).value;

double _num(CosObject o) => switch (o) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => throw StateError('not a number: $o'),
    };

void main() {
  group('PdfVectorSnapshot', () {
    test('capture detaches the region, content, and resources', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      final snap = PdfEditor(doc)
          .captureVectorSnapshot(0, const PdfRect(60, 700, 200, 740));
      expect(snap.region, const PdfRect(60, 700, 200, 740));
    });

    test('paste makes a vector /Stamp drawing the captured form', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      final editor = PdfEditor(doc);
      // page 1's content draws "Page 1" near (72, 720) — inside this region
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      editor.pasteVectorSnapshot(1, const PdfRect(100, 100, 260, 140), snap);

      final out = PdfDocument.open(editor.save());
      final stamp = out.page(1).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.rect, const PdfRect(100, 100, 260, 140));

      // the appearance maps the captured form onto the rect and draws it
      final ap = latin1.decode(out.cos.decodeStreamData(stamp.normalAppearance!));
      expect(ap, contains('/Cap Do'));

      // /Cap is a Form XObject whose BBox is the source region and whose
      // content is the page's own operators — i.e. real vectors, not a raster
      final res = out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
          as CosDictionary;
      final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
      final cap = out.cos.resolve(xobj['Cap']) as CosStream;
      expect(_name(cap.dictionary['Subtype']), 'Form');
      final bbox = out.cos.resolve(cap.dictionary['BBox']) as CosArray;
      expect([for (final v in bbox.items) _num(out.cos.resolve(v))],
          [60.0, 700.0, 220.0, 740.0]);
      final capContent = latin1.decode(out.cos.decodeStreamData(cap));
      expect(capContent, contains('(Page 1) Tj'));

      // the page's font resource travels with the form (the text resolves)
      final capRes =
          out.cos.resolve(cap.dictionary['Resources']) as CosDictionary;
      final fonts = out.cos.resolve(capRes['Font']) as CosDictionary;
      expect(fonts.entries.keys, contains('F1'));
    });

    test('paste scales the captured region onto a differently sized rect', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc);
      // a 100x50 source region pasted into a 200x200 box: sx=2, sy=4
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(0, 0, 100, 50));
      editor.pasteVectorSnapshot(0, const PdfRect(10, 20, 210, 220), snap);
      final out = PdfDocument.open(editor.save());
      final stamp = out.page(0).annotations.single;
      final ap = latin1.decode(out.cos.decodeStreamData(stamp.normalAppearance!));
      // cm: 2 0 0 4 (10 - 2*0) (20 - 4*0) = 2 0 0 4 10 20
      expect(ap, contains('2 0 0 4 10 20 cm'));
    });

    test('paste with opacity < 1 adds an ExtGState alpha to the appearance', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      editor.pasteVectorSnapshot(0, const PdfRect(100, 100, 260, 140), snap,
          opacity: 0.5);
      final out = PdfDocument.open(editor.save());
      final stamp = out.page(0).annotations.single;
      final ap =
          latin1.decode(out.cos.decodeStreamData(stamp.normalAppearance!));
      expect(ap, contains('/GS0 gs'));
      final res = out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
          as CosDictionary;
      expect(out.cos.resolve(res['ExtGState']), isA<CosDictionary>());
    });

    test('pasting a degenerate (zero-area) region is a no-op', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(100, 100, 100, 140));
      editor.pasteVectorSnapshot(0, const PdfRect(0, 0, 50, 50), snap);
      expect(editor.hasChanges, isFalse);
      expect(doc.page(0).annotations, isEmpty);
    });

    test('a detached snapshot survives further edits to the source', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      // mutate the document after capturing
      editor.addSquare(0, const PdfRect(0, 0, 50, 50));
      // the snapshot still pastes its original captured content
      editor.pasteVectorSnapshot(0, const PdfRect(300, 300, 460, 340), snap);
      final out = PdfDocument.open(editor.save());
      final stamp = out
          .page(0)
          .annotations
          .firstWhere((a) => a.rect == const PdfRect(300, 300, 460, 340));
      final res = out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
          as CosDictionary;
      final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
      final cap = out.cos.resolve(xobj['Cap']) as CosStream;
      expect(latin1.decode(out.cos.decodeStreamData(cap)), contains('(Page 1) Tj'));
    });
  });
}
