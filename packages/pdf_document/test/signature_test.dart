import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// 2x2 RGBA PNG (from png_test.dart), used as a handwritten-signature graphic.
final _png = base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGUlEQVR4nGP4z8DwHwgb'
    'WBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

final key = RsaPrivateKey.fromPem(testSignerKeyPem);
final cert = pemBytes(testSignerCertPem);
final signedAt = DateTime.utc(2026, 6, 10, 12, 0, 0);

Uint8List signedFixture() {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
  return editor.saveSigned(
    privateKey: key,
    certificates: [cert],
    reason: 'Approval',
    location: 'Melbourne',
    signingTime: signedAt,
  );
}

/// A one-page PDF with an AcroForm holding one empty signature field
/// "ApproverSig" whose widget sits on the page.
Uint8List buildEmptySigFieldPdf() {
  const content = 'BT /F1 24 Tf 72 720 Td (Sign here) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [6 0 R] '
        '/SigFlags 3 >> >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> /Annots [6 0 R] >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /FT /Sig /T (ApproverSig) /Type /Annot /Subtype /Widget '
        '/Rect [100 100 300 150] /F 4 /P 3 0 R >>',
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
  return ascii(buffer.toString());
}

/// The decoded content of a field's /AP /N appearance form, or null.
String? appearanceContent(PdfDocument doc, PdfFormField field) {
  final widget = field.widgets.first;
  final ap = doc.cos.resolve(widget['AP']);
  if (ap is! CosDictionary) return null;
  final n = doc.cos.resolve(ap['N']);
  if (n is! CosStream) return null;
  return String.fromCharCodes(doc.cos.decodeStreamData(n));
}

/// All the text shown by an appearance's `(...) Tj` operators, joined with
/// spaces so word-wrapped lines read back as the original strings.
String shownText(String content) => RegExp(r'\(([^)]*)\) Tj')
    .allMatches(content)
    .map((m) => m.group(1))
    .join(' ');

void main() {
  group('visible signature box', () {
    test('a placed appearance draws the Acrobat-style box', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        reason: 'Approval',
        location: 'Melbourne',
        signingTime: signedAt,
        appearance: const PdfSignatureAppearance(
          rect: PdfRect(72, 600, 320, 700),
        ),
      );
      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      expect(signature.validate().intact, isTrue);

      // the widget is visible at the requested rectangle
      final widget = signature.field.widgets.first;
      final rect = doc.cos.resolve(widget['Rect']) as CosArray;
      expect((doc.cos.resolve(rect[0]) as CosReal).value, 72);
      expect((doc.cos.resolve(rect[3]) as CosReal).value, 700);

      // the appearance form has a BBox matching the box size and shows the
      // signer name, date, reason and location
      final ap = doc.cos.resolve(widget['AP']) as CosDictionary;
      final form = doc.cos.resolve(ap['N']) as CosStream;
      final bbox = doc.cos.resolve(form.dictionary['BBox']) as CosArray;
      expect((doc.cos.resolve(bbox[2]) as CosReal).value, 248); // 320-72
      expect((doc.cos.resolve(bbox[3]) as CosReal).value, 100); // 700-600

      final shown = shownText(appearanceContent(doc, signature.field)!);
      expect(shown, contains('Digitally signed by Dart PDF Test Signer'));
      expect(shown, contains('Date: 2026.06.10 12:00:00'));
      expect(shown, contains('Reason: Approval'));
      expect(shown, contains('Location: Melbourne'));
    });

    test('placing on a later page attaches the widget to that page', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        signingTime: signedAt,
        appearance: const PdfSignatureAppearance(
          page: 2,
          rect: PdfRect(100, 100, 300, 160),
        ),
      );
      final doc = PdfDocument.open(signed);
      final annots0 = doc.cos.resolve(doc.page(0).dict['Annots']);
      expect(annots0 is CosArray ? annots0.length : 0, 0);
      final annots2 = doc.cos.resolve(doc.page(2).dict['Annots']) as CosArray;
      expect(annots2.length, 1);
      expect(PdfSignature.of(doc).single.validate().intact, isTrue);
    });

    test('signing an existing visible field fills its box', () {
      final editor = PdfEditor(PdfDocument.open(buildEmptySigFieldPdf()));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        fieldName: 'ApproverSig',
        reason: 'Reviewed',
        signingTime: signedAt,
      );
      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      expect(signature.validate().intact, isTrue);
      final content = appearanceContent(doc, signature.field);
      expect(content, isNotNull);
      expect(content, contains('Digitally signed by'));
      expect(content, contains('Reason: Reviewed'));
    });

    test('showing fewer fields omits them from the box', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        reason: 'Approval',
        location: 'Melbourne',
        signingTime: signedAt,
        appearance: const PdfSignatureAppearance(
          rect: PdfRect(72, 600, 320, 700),
          showReason: false,
          showLocation: false,
        ),
      );
      final doc = PdfDocument.open(signed);
      final shown =
          shownText(appearanceContent(doc, PdfSignature.of(doc).single.field)!);
      expect(shown, contains('Digitally signed by'));
      expect(shown, isNot(contains('Reason:')));
      expect(shown, isNot(contains('Location:')));
    });

    test('a graphic renders in the left panel as an image XObject', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        signingTime: signedAt,
        appearance: PdfSignatureAppearance(
          rect: const PdfRect(72, 600, 320, 700),
          graphic: PdfEmbeddableImage.png(_png),
        ),
      );
      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      expect(signature.validate().intact, isTrue);

      final widget = signature.field.widgets.first;
      final ap = doc.cos.resolve(widget['AP']) as CosDictionary;
      final form = doc.cos.resolve(ap['N']) as CosStream;
      final resources =
          doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
      final xobjects = doc.cos.resolve(resources['XObject']) as CosDictionary;
      expect(xobjects.entries.keys, contains('SigImg'));

      final content = String.fromCharCodes(doc.cos.decodeStreamData(form));
      expect(content, contains('/SigImg Do'));
      // the big name text is replaced by the graphic in the left panel
      expect(shownText(content), isNot(contains('Dart PDF Test Signer Dart')));
    });

    test('a background image covers the box behind the text, clipped', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        signingTime: signedAt,
        appearance: PdfSignatureAppearance(
          rect: const PdfRect(72, 600, 320, 700),
          backgroundImage: PdfEmbeddableImage.png(_png),
        ),
      );
      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      expect(signature.validate().intact, isTrue);

      final widget = signature.field.widgets.first;
      final ap = doc.cos.resolve(widget['AP']) as CosDictionary;
      final form = doc.cos.resolve(ap['N']) as CosStream;
      final resources =
          doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
      final xobjects = doc.cos.resolve(resources['XObject']) as CosDictionary;
      expect(xobjects.entries.keys, contains('SigBg'));

      final content = String.fromCharCodes(doc.cos.decodeStreamData(form));
      // clipped to the box and drawn before the border stroke, and the
      // signer name still renders on top (not replaced, unlike /graphic).
      expect(content, contains('W'));
      expect(content, contains('/SigBg Do'));
      expect(content.indexOf('/SigBg Do'), lessThan(content.indexOf('S\n')));
      expect(shownText(content), contains('Digitally signed by'));
    });

    test('a details-only box (no name/graphic) omits the left panel', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        reason: 'Approval',
        signingTime: signedAt,
        appearance: const PdfSignatureAppearance(
          rect: PdfRect(72, 600, 320, 700),
          backgroundColor: 0xEEF3F8,
          showName: false,
        ),
      );
      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      expect(signature.validate().intact, isTrue);
      final content = appearanceContent(doc, signature.field)!;
      // background fill rectangle emitted before the border
      expect(content, contains('0 0 248 100 re'));
      final shown = shownText(content);
      expect(shown, isNot(contains('Digitally signed by')));
      expect(shown, contains('Reason: Approval'));
    });

    test('no appearance keeps an invisible field (backward compatible)', () {
      final doc = PdfDocument.open(signedFixture());
      final signature = PdfSignature.of(doc).single;
      expect(appearanceContent(doc, signature.field), isNull);
      final widget = signature.field.widgets.first;
      final rect = doc.cos.resolve(widget['Rect']) as CosArray;
      expect((doc.cos.resolve(rect[2]) as CosInteger).value, 0);
    });
  });

  group('signing', () {
    test('a signed document validates as intact and whole', () {
      final doc = PdfDocument.open(signedFixture());
      final signatures = PdfSignature.of(doc);
      expect(signatures, hasLength(1));
      final signature = signatures.single;
      expect(signature.field.name, 'Signature1');
      expect(signature.signerName, 'Dart PDF Test Signer');
      expect(signature.reason, 'Approval');
      expect(signature.location, 'Melbourne');
      expect(signature.subFilter, 'adbe.pkcs7.detached');
      expect(signature.signingTime, signedAt);

      final result = signature.validate();
      expect(result.problems, isEmpty);
      expect(result.intact, isTrue);
      expect(result.digestMatches, isTrue);
      expect(result.signatureValid, isTrue);
      expect(result.coversWholeDocument, isTrue);
      expect(result.signedAt, signedAt);
      expect(result.signerCertificate?.subjectCommonName,
          'Dart PDF Test Signer');
    });

    test('the signature field lands in the AcroForm and on the page', () {
      final doc = PdfDocument.open(signedFixture());
      final form = PdfAcroForm.of(doc)!;
      final field = form.fieldNamed('Signature1')!;
      expect(field.type, PdfFieldType.signature);
      final annots = doc.cos.resolve(doc.page(0).dict['Annots']) as CosArray;
      expect(annots.length, 1);
      final acroForm =
          doc.cos.resolve(doc.catalog['AcroForm']) as CosDictionary;
      expect((doc.cos.resolve(acroForm['SigFlags']) as CosInteger).value, 3);
    });

    test('signing keeps the original bytes (incremental update)', () {
      final original = buildMultiPagePdf(2);
      final editor = PdfEditor(PdfDocument.open(original));
      final signed = editor.saveSigned(
          privateKey: key, certificates: [cert], signingTime: signedAt);
      expect(signed.sublist(0, original.length), original);
    });

    test('an existing empty signature field is reused', () {
      final editor = PdfEditor(PdfDocument.open(buildEmptySigFieldPdf()));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        fieldName: 'ApproverSig',
        signingTime: signedAt,
      );
      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      expect(signature.field.name, 'ApproverSig');
      expect(signature.validate().intact, isTrue);
      // no second field materialized
      expect(PdfAcroForm.of(doc)!.fields, hasLength(1));
    });

    test('queued edits become part of the signed revision', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..removePage(2);
      final doc = PdfDocument.open(editor.saveSigned(
          privateKey: key, certificates: [cert], signingTime: signedAt));
      expect(doc.pageCount, 2);
      expect(PdfSignature.of(doc).single.validate().intact, isTrue);
    });
  });

  group('validation', () {
    test('a flipped byte in the signed range breaks the digest', () {
      final signed = signedFixture();
      signed[40] ^= 0x01; // inside page 1's content
      final doc = PdfDocument.open(signed);
      final result = PdfSignature.of(doc).single.validate();
      expect(result.digestMatches, isFalse);
      expect(result.intact, isFalse);
    });

    test('editing after signing demotes coverage but not integrity', () {
      final signedDoc = PdfDocument.open(signedFixture());
      final editor = PdfEditor(signedDoc)..rotatePage(0, 90);
      final doc = PdfDocument.open(editor.save());
      final result = PdfSignature.of(doc).single.validate();
      expect(result.intact, isTrue);
      expect(result.coversWholeDocument, isFalse);
      expect(result.problems.single, contains('updated after'));
    });

    test('a second signature signs the updated whole', () {
      final once = PdfDocument.open(signedFixture());
      final twice = PdfDocument.open(PdfEditor(once).saveSigned(
          privateKey: key,
          certificates: [cert],
          reason: 'Countersign',
          signingTime: signedAt.add(const Duration(days: 1))));
      final signatures = PdfSignature.of(twice);
      expect(signatures, hasLength(2));
      expect(signatures[0].field.name, 'Signature1');
      expect(signatures[1].field.name, 'Signature2');

      final first = signatures[0].validate();
      expect(first.intact, isTrue);
      expect(first.coversWholeDocument, isFalse);

      final second = signatures[1].validate();
      expect(second.intact, isTrue);
      expect(second.coversWholeDocument, isTrue);
    });

    test('a tampered CMS blob fails signature verification', () {
      final signed = signedFixture();
      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      // flip a bit inside the stored signature container itself: find the
      // hex contents and corrupt one digit of the embedded RSA signature
      final contents = signature.contents;
      expect(contents, isNot(everyElement(0)));
      // corrupt the last DER byte (inside the RSA signature octets)
      var end = contents.length - 1;
      while (end > 0 && contents[end] == 0) {
        end--;
      }
      contents[end] ^= 0xFF;
      final result = signature.validate();
      expect(result.signatureValid, isFalse);
      expect(result.digestMatches, isTrue);
    });
  });

  group('chain of trust', () {
    // safely inside the test certificates' 20-year validity window
    final chainSignedAt = DateTime.utc(2027, 1, 1, 12);

    Uint8List chainSignedFixture() {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      return editor.saveSigned(
        privateKey: RsaPrivateKey.fromPem(testChainSignerKeyPem),
        certificates: [
          pemBytes(testChainSignerCertPem),
          pemBytes(testCaCertPem),
        ],
        signingTime: chainSignedAt,
      );
    }

    test('without a trust store the verdict stays null', () {
      final doc = PdfDocument.open(chainSignedFixture());
      final result = PdfSignature.of(doc).single.validate();
      expect(result.intact, isTrue);
      expect(result.chainTrusted, isNull);
      expect(result.trustChain, isEmpty);
    });

    test('a CA-signed signature chains to the trusted root', () {
      final doc = PdfDocument.open(chainSignedFixture());
      final store = PdfTrustStore()..addPem(testCaCertPem);
      final result =
          PdfSignature.of(doc).single.validate(trustStore: store);
      expect(result.intact, isTrue);
      expect(result.chainTrusted, isTrue);
      expect(result.chainProblems, isEmpty);
      expect(result.trustChain.first.subjectCommonName,
          'Dart PDF Chain Signer');
      expect(result.trustChain.last.subjectCommonName, 'Dart PDF Test CA');
    });

    test('an unrelated trust store rejects the chain', () {
      final doc = PdfDocument.open(chainSignedFixture());
      final store = PdfTrustStore()..addPem(testSignerCertPem);
      final result =
          PdfSignature.of(doc).single.validate(trustStore: store);
      expect(result.intact, isTrue, reason: 'integrity is separate');
      expect(result.chainTrusted, isFalse);
      expect(result.chainProblems, isNotEmpty);
    });

    test('a directly trusted self-signed signer passes', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final doc = PdfDocument.open(editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        signingTime: chainSignedAt,
      ));
      final store = PdfTrustStore()..addPem(testSignerCertPem);
      final result =
          PdfSignature.of(doc).single.validate(trustStore: store);
      expect(result.chainTrusted, isTrue);
      final empty = PdfSignature.of(doc)
          .single
          .validate(trustStore: PdfTrustStore());
      expect(empty.chainTrusted, isFalse);
    });
  });
}
