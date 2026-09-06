// Vector snapshots (PdfVectorSnapshot): capturing a region of a page as
// detached vector graphics and pasting it back as a /Stamp annotation
// whose appearance *draws* the captured content (so it stays vector).
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

String _name(CosObject? o) => (o as CosName).value;

/// A one-page PDF whose content sets a red fill and a green stroke, then
/// paints a filled+stroked rectangle - so a recolour has real colour
/// operators to rewrite (the shared fixtures draw only default-black text).
Uint8List _coloredPagePdf() {
  const content = '1 0 0 rg 0 1 0 RG 10 10 100 100 re B';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
        '/Contents 4 0 R /Resources << >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
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
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// A one-page PDF whose content draws a **nested** Form XObject (/Fm0) that
/// sets its own blue fill - so a recolour has to recurse into the nested form,
/// not just rewrite the top-level content.
Uint8List _nestedFormPagePdf() {
  const pageContent = '/Fm0 Do';
  const formContent = '0 0 1 rg 0 0 50 50 re f';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
        '/Contents 4 0 R /Resources << /XObject << /Fm0 5 0 R >> >> >>',
    '<< /Length ${pageContent.length} >>\nstream\n$pageContent\nendstream',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] '
        '/Length ${formContent.length} >>\nstream\n$formContent\nendstream',
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
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

String _capContent(PdfDocument out, PdfAnnotation stamp) {
  final res = out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
      as CosDictionary;
  final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
  final cap = out.cos.resolve(xobj['Cap']) as CosStream;
  return latin1.decode(out.cos.decodeStreamData(cap));
}

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
      // page 1's content draws "Page 1" near (72, 720) - inside this region
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      editor.pasteVectorSnapshot(1, const PdfRect(100, 100, 260, 140), snap);

      final out = PdfDocument.open(editor.save());
      final stamp = out.page(1).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.rect, const PdfRect(100, 100, 260, 140));

      // the appearance maps the captured form onto the rect and draws it
      final ap =
          latin1.decode(out.cos.decodeStreamData(stamp.normalAppearance!));
      expect(ap, contains('/Cap Do'));

      // /Cap is a Form XObject in an upright [0 0 dW dH] box whose content
      // is the page's own operators under the capture matrix - i.e. real
      // vectors, not a raster
      final res =
          out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
              as CosDictionary;
      final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
      final cap = out.cos.resolve(xobj['Cap']) as CosStream;
      expect(_name(cap.dictionary['Subtype']), 'Form');
      final bbox = out.cos.resolve(cap.dictionary['BBox']) as CosArray;
      // an unrotated page: the box is the region's size at the origin
      expect([for (final v in bbox.items) _num(out.cos.resolve(v))],
          [0.0, 0.0, 160.0, 40.0]);
      final capContent = latin1.decode(out.cos.decodeStreamData(cap));
      expect(capContent, contains('(Page 1) Tj'));
      // the capture matrix translates the region's origin to the box origin
      expect(capContent, contains('1 0 0 1 -60 -700 cm'));

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
      final ap =
          latin1.decode(out.cos.decodeStreamData(stamp.normalAppearance!));
      // cm: 2 0 0 4 (10 - 2*0) (20 - 4*0) = 2 0 0 4 10 20
      expect(ap, contains('2 0 0 4 10 20 cm'));
    });

    test('capture bakes the page /Rotate (90° swaps the displayed size)', () {
      final doc = PdfDocument.open(buildNestedPageTreePdf());
      expect(doc.page(0).rotation, 90); // sanity: page 0 is rotated
      final editor = PdfEditor(doc);
      // a 300x200 user-space region on a 90° page displays as 200x300
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(50, 50, 350, 250));
      expect(snap.displayWidth, 200);
      expect(snap.displayHeight, 300);

      editor.pasteVectorSnapshot(0, const PdfRect(0, 0, 200, 300), snap);
      final out = PdfDocument.open(editor.save());
      final stamp = out.page(0).annotations.single;
      final res =
          out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
              as CosDictionary;
      final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
      final cap = out.cos.resolve(xobj['Cap']) as CosStream;
      final bbox = out.cos.resolve(cap.dictionary['BBox']) as CosArray;
      expect([for (final v in bbox.items) _num(out.cos.resolve(v))],
          [0.0, 0.0, 200.0, 300.0]);
      // the baked rotation cm for a 90° page: [0 -1 1 0 -ry0 rx1]
      expect(latin1.decode(out.cos.decodeStreamData(cap)),
          contains('0 -1 1 0 -50 350 cm'));
    });

    test('repeat pastes of one snapshot share a single captured form', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      final ref1 =
          editor.pasteVectorSnapshot(0, const PdfRect(0, 0, 160, 40), snap);
      final ref2 = editor.pasteVectorSnapshot(
          0, const PdfRect(200, 0, 360, 40), snap,
          sharedObject: ref1);
      expect(ref2, ref1); // the second paste reuses the first form

      final out = PdfDocument.open(editor.save());
      final stamps = out.page(0).annotations;
      expect(stamps, hasLength(2));
      int capNum(PdfAnnotation a) {
        final res = out.cos.resolve(a.normalAppearance!.dictionary['Resources'])
            as CosDictionary;
        final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
        // stored as an indirect reference, not resolved inline
        return (xobj.entries['Cap'] as CosReference).objectNumber;
      }

      expect(capNum(stamps[0]), capNum(stamps[1]));
    });

    test('paste with a stale shared object re-materializes the form', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      // a bogus object number doesn't resolve to a form - paste makes its own
      final ref = editor.pasteVectorSnapshot(
          0, const PdfRect(0, 0, 160, 40), snap,
          sharedObject: 99999);
      expect(ref, isNot(99999));
      expect(ref, greaterThan(0));
      final out = PdfDocument.open(editor.save());
      final stamp = out.page(0).annotations.single;
      final res =
          out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
              as CosDictionary;
      final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
      expect(out.cos.resolve(xobj['Cap']), isA<CosStream>());
    });

    test('paste with opacity < 1 adds an ExtGState alpha to the appearance',
        () {
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
      final res =
          out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
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

    test('toPdfBytes writes a one-page PDF sized to the captured region', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final snap = PdfEditor(doc)
          .captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));

      final pdf = PdfDocument.open(snap.toPdfBytes());
      expect(pdf.pageCount, 1);
      // the page is exactly the captured region (160x40 at the origin)
      expect(pdf.page(0).mediaBox, const PdfRect(0, 0, 160, 40));
      // and it draws the captured vectors, with the page font carried along
      final content = latin1.decode(pdf.page(0).contentBytes());
      expect(content, contains('(Page 1) Tj'));
      expect(content, contains('1 0 0 1 -60 -700 cm'));
    });

    test(
        'toPdfBytes hoists resource streams (an image XObject) to indirect '
        'objects', () {
      // a page whose /Resources carry an image XObject — i.e. a stream that
      // can't live inline once another object references it (§7.3.8)
      final base = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      base.stampPage(
          0,
          (s) => s.jpegImage(buildTestJpeg(),
              x: 50, y: 700, width: 80, height: 80));
      final doc = PdfDocument.open(base.save());

      final snap = PdfEditor(doc)
          .captureVectorSnapshot(0, const PdfRect(40, 690, 140, 790));
      final pdf = PdfDocument.open(snap.toPdfBytes());

      // the image rode along as an indirect stream, not an inline one
      final res = pdf.cos.resolve(pdf.page(0).resources) as CosDictionary;
      final xobj = pdf.cos.resolve(res['XObject']) as CosDictionary;
      expect(xobj.entries, isNotEmpty);
      for (final value in xobj.entries.values) {
        expect(value, isA<CosReference>());
        expect(pdf.cos.resolve(value), isA<CosStream>());
      }
    });

    for (final rotation in [0, 90, 180, 270]) {
      test('PDF interchange preserves crop offsets and rotation $rotation', () {
        final editor = PdfEditor(PdfDocument.open(_nestedFormPagePdf()));
        editor.rotatePages([0], rotation);
        final source = PdfDocument.open(editor.save());
        final snapshot = PdfEditor(source)
            .captureVectorSnapshot(0, const PdfRect(10, 20, 110, 70));
        final bytes = snapshot.toPdfBytes();
        expect(snapshot.toPdfBytes(), bytes,
            reason: 'export must not mutate resources');
        final out = PdfDocument.open(bytes);
        expect(out.page(0).rotation, 0);
        expect(out.page(0).mediaBox.width, rotation % 180 == 0 ? 100 : 50);
        expect(out.page(0).mediaBox.height, rotation % 180 == 0 ? 50 : 100);
        final imported = PdfVectorSnapshot.fromPdfBytes(bytes);
        expect(imported.displayWidth, snapshot.displayWidth);
        expect(imported.displayHeight, snapshot.displayHeight);
        final xobjects =
            out.cos.resolve(out.page(0).resources['XObject']) as CosDictionary;
        final form = out.cos.resolve(xobjects['Fm0']) as CosStream;
        expect(latin1.decode(out.cos.decodeStreamData(form)),
            contains('0 0 1 rg'));
      });
    }

    test('import takes the first page and rejects unreadable or empty PDFs',
        () {
      final snapshot = PdfVectorSnapshot.fromPdfBytes(buildMultiPagePdf(2));
      final out = PdfDocument.open(snapshot.toPdfBytes());
      expect(out.pageCount, 1);
      expect(latin1.decode(out.page(0).contentBytes()), contains('(Page 1)'));
      expect(() => PdfVectorSnapshot.fromPdfBytes(Uint8List(0)),
          throwsA(anything));
      expect(() => PdfVectorSnapshot.fromPdfBytes(buildMultiPagePdf(0)),
          throwsA(anything));
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      expect(
          () => editor
              .captureVectorSnapshot(0, const PdfRect(0, 0, 0, 20))
              .toPdfBytes(),
          throwsFormatException);
    });

    test('export hoists array lookup streams and keeps small resource numbers',
        () {
      final source = PdfDocument.open(_nestedFormPagePdf());
      final lookup = Uint8List.fromList([255, 0, 0, 0, 0, 255]);
      source.page(0).resources['ColorSpace'] = CosDictionary({
        'Palette': CosArray([
          const CosName('Indexed'),
          const CosName('DeviceRGB'),
          CosInteger(1),
          CosStream(CosDictionary(), lookup)
        ]),
      });
      final form = source.cos.resolve(
              (source.page(0).resources['XObject'] as CosDictionary)['Fm0'])
          as CosStream;
      form.dictionary['Matrix'] = CosArray([
        CosReal(0.0000123456789),
        CosInteger(0),
        CosInteger(0),
        CosReal(0.0000123456789),
        CosInteger(0),
        CosInteger(0)
      ]);
      final snapshot = PdfEditor(source)
          .captureVectorSnapshot(0, const PdfRect(0, 0, 100, 100));
      final out = PdfDocument.open(snapshot.toPdfBytes());
      final spaces = out.page(0).resources['ColorSpace'] as CosDictionary;
      final palette = spaces['Palette'] as CosArray;
      expect(palette[3], isA<CosReference>());
      expect(out.cos.decodeStreamData(out.cos.resolve(palette[3]) as CosStream),
          lookup);
      final outForm = out.cos.resolve(
              (out.page(0).resources['XObject'] as CosDictionary)['Fm0'])
          as CosStream;
      expect(
          _num((outForm.dictionary['Matrix'] as CosArray)[0]), 0.0000123456789);
    });

    test('password-protected PDF imports to an unencrypted standalone PDF', () {
      final encrypted = buildEncryptedPdf(revision: 4, userPassword: 'secret');
      expect(() => PdfVectorSnapshot.fromPdfBytes(encrypted),
          throwsA(isA<CosPasswordException>()));
      final snapshot =
          PdfVectorSnapshot.fromPdfBytes(encrypted, password: 'secret');
      final out = PdfDocument.open(snapshot.toPdfBytes());
      expect(out.cos.isEncrypted, isFalse);
      expect(latin1.decode(out.page(0).contentBytes()),
          contains('(Hello, world!)'));
    });

    test('fromPdfBytes re-imports a snapshot written by toPdfBytes', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final original = PdfEditor(doc)
          .captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));

      // round-trip through the interchange PDF, then paste into a fresh doc
      final reimported = PdfVectorSnapshot.fromPdfBytes(original.toPdfBytes());
      expect(reimported.displayWidth, original.displayWidth);
      expect(reimported.displayHeight, original.displayHeight);

      final target = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(target);
      editor.pasteVectorSnapshot(
          0, const PdfRect(100, 100, 260, 140), reimported);
      final out = PdfDocument.open(editor.save());
      final stamp = out.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      // the captured vectors survived the PDF round-trip
      final res =
          out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
              as CosDictionary;
      final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
      final cap = out.cos.resolve(xobj['Cap']) as CosStream;
      expect(latin1.decode(out.cos.decodeStreamData(cap)),
          contains('(Page 1) Tj'));
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
      final res =
          out.cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
              as CosDictionary;
      final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
      final cap = out.cos.resolve(xobj['Cap']) as CosStream;
      expect(latin1.decode(out.cos.decodeStreamData(cap)),
          contains('(Page 1) Tj'));
    });
  });

  group('PdfVectorSnapshot recolour', () {
    test('paste marks the stamp as a vector snapshot', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      editor.pasteVectorSnapshot(0, const PdfRect(0, 0, 160, 40), snap);
      final stamp = doc.page(0).annotations.single;
      expect(editor.isVectorSnapshotStamp(stamp), isTrue);
    });

    test('an ordinary stamp is not a recolourable vector snapshot', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc)
        ..addStamp(0, const PdfRect(0, 0, 120, 40), 'APPROVED');
      final stamp = doc.page(0).annotations.single;
      expect(editor.isVectorSnapshotStamp(stamp), isFalse);
      expect(editor.recolorVectorSnapshot(0, stamp, 0xFF0000), isFalse);
    });

    test('recolour forces a single ink up front so default-black recolours',
        () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      editor.pasteVectorSnapshot(0, const PdfRect(0, 0, 160, 40), snap);
      final stamp = doc.page(0).annotations.single;
      expect(editor.recolorVectorSnapshot(0, stamp, 0xFF0000), isTrue);

      final out = PdfDocument.open(editor.save());
      final content = _capContent(out, out.page(0).annotations.single);
      // the fixture text carries no colour operator, so a leading ink is
      // forced for both paint sides - the text draws red now
      expect(content, contains('1 0 0 rg'));
      expect(content, contains('1 0 0 RG'));
      // the captured vectors survive
      expect(content, contains('(Page 1) Tj'));
    });

    test('recolour rewrites existing fill and stroke colours', () {
      final doc = PdfDocument.open(_coloredPagePdf());
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(0, 0, 200, 200));
      editor.pasteVectorSnapshot(0, const PdfRect(0, 0, 200, 200), snap);
      final stamp = doc.page(0).annotations.single;
      editor.recolorVectorSnapshot(0, stamp, 0x0000FF);

      final out = PdfDocument.open(editor.save());
      final content = _capContent(out, out.page(0).annotations.single);
      // the red fill and green stroke are gone, retinted blue; the path
      // paint operator survives
      expect(content, isNot(contains('1 0 0 rg')));
      expect(content, isNot(contains('0 1 0 RG')));
      expect(content, contains('0 0 1 rg'));
      expect(content, contains('0 0 1 RG'));
      expect(content, contains('re'));
    });

    test('recolour is isolated to the stamp - shared pastes keep their ink',
        () {
      final doc = PdfDocument.open(_coloredPagePdf());
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(0, 0, 200, 200));
      final ref1 =
          editor.pasteVectorSnapshot(0, const PdfRect(0, 0, 100, 100), snap);
      editor.pasteVectorSnapshot(0, const PdfRect(100, 100, 200, 200), snap,
          sharedObject: ref1);
      final stamps = doc.page(0).annotations;
      // recolour only the first paste
      editor.recolorVectorSnapshot(0, stamps[0], 0x0000FF);

      final out = PdfDocument.open(editor.save());
      final outStamps = out.page(0).annotations;
      expect(_capContent(out, outStamps[0]), contains('0 0 1 rg'));
      // the shared paste still references the original, un-recoloured form
      final other = _capContent(out, outStamps[1]);
      expect(other, contains('1 0 0 rg'));
      expect(other, isNot(contains('0 0 1 rg')));
    });

    test('recolour recurses into nested Form XObjects', () {
      final doc = PdfDocument.open(_nestedFormPagePdf());
      final editor = PdfEditor(doc);
      final snap =
          editor.captureVectorSnapshot(0, const PdfRect(0, 0, 200, 200));
      editor.pasteVectorSnapshot(0, const PdfRect(0, 0, 200, 200), snap);
      final stamp = doc.page(0).annotations.single;
      editor.recolorVectorSnapshot(0, stamp, 0xFF0000);

      final out = PdfDocument.open(editor.save());
      final s = out.page(0).annotations.single;
      final res = out.cos.resolve(s.normalAppearance!.dictionary['Resources'])
          as CosDictionary;
      final xobj = out.cos.resolve(res['XObject']) as CosDictionary;
      final cap = out.cos.resolve(xobj['Cap']) as CosStream;
      // the top capture still invokes the nested form
      expect(latin1.decode(out.cos.decodeStreamData(cap)), contains('/Fm0 Do'));
      // and the nested form's own blue fill is retinted red
      final capRes =
          out.cos.resolve(cap.dictionary['Resources']) as CosDictionary;
      final capXobj = out.cos.resolve(capRes['XObject']) as CosDictionary;
      final nested = out.cos.resolve(capXobj['Fm0']) as CosStream;
      final nestedContent = latin1.decode(out.cos.decodeStreamData(nested));
      expect(nestedContent, contains('1 0 0 rg'));
      expect(nestedContent, isNot(contains('0 0 1 rg')));
      expect(nestedContent, contains('re'));
    });

    test('recolour works on a snapshot loaded from a prior revision', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final first = PdfEditor(doc);
      final snap =
          first.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      first.pasteVectorSnapshot(0, const PdfRect(0, 0, 160, 40), snap);
      final mid = PdfDocument.open(first.save());

      final second = PdfEditor(mid);
      final stamp = mid.page(0).annotations.single;
      expect(second.recolorVectorSnapshot(0, stamp, 0x00FF00), isTrue);

      final out = PdfDocument.open(second.save());
      final content = _capContent(out, out.page(0).annotations.single);
      expect(content, contains('0 1 0 rg'));
      expect(content, contains('(Page 1) Tj'));
    });
  });
}
