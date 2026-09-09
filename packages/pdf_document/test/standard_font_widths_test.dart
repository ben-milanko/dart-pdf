// Base-14 metrics cover the whole WinAnsi range, not just ASCII.
//
// [ContentWriter.showText] emits Latin-1 bytes verbatim into appearances whose
// /Font dict declares /WinAnsiEncoding, so an accented name reaches the page as
// codes 0x80-0xFF. A viewer takes each advance from the font dict's /Widths;
// a code outside /FirstChar../LastChar advances by /MissingWidth, which
// defaults to 0 and piles the glyphs on top of each other.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

final key = RsaPrivateKey.fromPem(testSignerKeyPem);
final cert = pemBytes(testSignerCertPem);
final signedAt = DateTime.utc(2026, 6, 10, 12, 0, 0);

/// The /Font dict of the first resource in an appearance form's /Resources.
CosDictionary appearanceFont(PdfDocument doc, CosStream form) {
  final resources = doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
  final fonts = doc.cos.resolve(resources['Font']) as CosDictionary;
  return doc.cos.resolve(fonts.entries.values.first) as CosDictionary;
}

/// The signature widget's /AP /N form.
CosStream signatureAppearance(PdfDocument doc) {
  final widget = PdfSignature.of(doc).single.field.widgets.first;
  final ap = doc.cos.resolve(widget['AP']) as CosDictionary;
  return doc.cos.resolve(ap['N']) as CosStream;
}

void main() {
  group('PdfStandardFont metrics span WinAnsi', () {
    test('the tables carry 224 entries (codes 32-255)', () {
      for (final font in PdfStandardFont.values) {
        expect(font.widths, hasLength(224), reason: font.baseFont);
      }
    });

    test('accented codes carry their real AFM advance, not the fallback', () {
      // Adobe Helvetica.afm: eacute 556, Ccedilla 722, AE 1000, igrave 278.
      expect(PdfStandardFont.helvetica.widthOf(0xE9), 556); // é
      expect(PdfStandardFont.helvetica.widthOf(0xC7), 722); // Ç
      expect(PdfStandardFont.helvetica.widthOf(0xC6), 1000); // Æ
      expect(PdfStandardFont.helvetica.widthOf(0xEC), 278); // ì
      // Times-Roman.afm: eacute 444, Ccedilla 667, AE 889, germandbls 500.
      expect(PdfStandardFont.times.widthOf(0xE9), 444);
      expect(PdfStandardFont.times.widthOf(0xC7), 667);
      expect(PdfStandardFont.times.widthOf(0xC6), 889);
      expect(PdfStandardFont.times.widthOf(0xDF), 500);
    });

    test('an accented glyph is not measured as its unaccented base', () {
      // í is far narrower than i is wide in Times - the give-away that a
      // base-letter approximation is being used instead of real metrics.
      expect(PdfStandardFont.times.widthOf(0xED), isNot(444)); // í != a
      expect(PdfStandardFont.helvetica.widthOf(0xED), 278); // í
      expect(PdfStandardFont.helvetica.widthOf(0x69), 222); // i
    });

    test('codes WinAnsi leaves undefined carry the bullet width', () {
      // ISO 32000-1 Annex D.2: unused WinAnsi codes render as bullet.
      final bullet = PdfStandardFont.helvetica.widthOf(0x95);
      expect(bullet, 350);
      for (final unused in [0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D]) {
        expect(PdfStandardFont.helvetica.widthOf(unused), bullet);
      }
    });

    test('no advance in a written table is zero', () {
      for (final font in PdfStandardFont.values) {
        expect(font.widths.where((w) => w == 0), isEmpty,
            reason: '${font.baseFont} would advance by 0 somewhere');
      }
    });

    test('widthOf agrees with the emitted array across the whole range', () {
      for (final font in PdfStandardFont.values) {
        final widths = font.widths;
        for (var code = 32; code <= 255; code++) {
          expect(font.widthOf(code), widths[code - 32],
              reason: '${font.baseFont} code $code');
        }
      }
    });

    test('Courier stays monospaced across the wider range', () {
      expect(PdfStandardFont.courier.widths, everyElement(600));
      expect(PdfStandardFont.courier.widthOf(0xE9), 600);
    });

    test('codes outside 32-255 still fall back', () {
      expect(PdfStandardFont.helvetica.widthOf(31),
          PdfStandardFont.helvetica.widthOf(256));
    });

    test('measureHelvetica counts accents at their own width', () {
      // "é" alone: 556/1000 em, not the 556 average that happened to match.
      expect(measureHelvetica('í', 10), closeTo(2.78, 0.001));
      expect(measureHelvetica('é', 10), closeTo(5.56, 0.001));
    });
  });

  group('written /Font dicts declare the range they measure', () {
    test('a signature appearance font spans 32-255 with 224 widths', () {
      final signed = PdfEditor(PdfDocument.open(buildMultiPagePdf(1))).saveSigned(
        privateKey: key,
        certificates: [cert],
        signerName: 'José Muñoz',
        signingTime: signedAt,
        appearance: const PdfSignatureAppearance(
          rect: PdfRect(72, 600, 320, 700),
        ),
      );
      final doc = PdfDocument.open(signed);
      final font = appearanceFont(doc, signatureAppearance(doc));

      expect(doc.cos.resolve(font['Encoding']), const CosName('WinAnsiEncoding'));
      expect((doc.cos.resolve(font['FirstChar']) as CosInteger).value, 32);
      expect((doc.cos.resolve(font['LastChar']) as CosInteger).value, 255);
      final widths = doc.cos.resolve(font['Widths']) as CosArray;
      expect(widths.items, hasLength(224));
      // the array is this face's own metrics, so é (0xE9) and ñ (0xF1) carry
      // a real advance rather than falling off the end of the array
      final baseFont = (doc.cos.resolve(font['BaseFont']) as CosName).value;
      final face = PdfStandardFont.values
          .firstWhere((f) => f.baseFont == baseFont);
      for (final code in [0xE9, 0xF1]) {
        final width = (doc.cos.resolve(widths[code - 32]) as CosInteger).value;
        expect(width, face.widthOf(code));
        expect(width, greaterThan(0));
      }
    });

    test('every byte the appearance shows has an entry in its /Widths', () {
      final signed = PdfEditor(PdfDocument.open(buildMultiPagePdf(1))).saveSigned(
        privateKey: key,
        certificates: [cert],
        signerName: 'Renée Ångström',
        reason: 'Approuvé',
        location: 'Genève',
        signingTime: signedAt,
        appearance: const PdfSignatureAppearance(
          rect: PdfRect(72, 600, 320, 700),
        ),
      );
      final doc = PdfDocument.open(signed);
      final form = signatureAppearance(doc);
      final font = appearanceFont(doc, form);
      final first = (doc.cos.resolve(font['FirstChar']) as CosInteger).value;
      final widths = doc.cos.resolve(font['Widths']) as CosArray;

      final content = Uint8List.fromList(doc.cos.decodeStreamData(form));
      final shown = RegExp(r'\(([^)]*)\) Tj')
          .allMatches(String.fromCharCodes(content))
          .expand((m) => m.group(1)!.codeUnits)
          .toSet();
      expect(shown, isNotEmpty);
      // the accented bytes really did reach the content stream
      expect(shown.any((c) => c > 0x7F), isTrue);
      for (final code in shown) {
        if (code == 0x5C) continue; // escape prefix, not a shown glyph
        final index = code - first;
        expect(index, inInclusiveRange(0, widths.items.length - 1),
            reason: 'code $code has no /Widths entry');
        expect((doc.cos.resolve(widths[index]) as CosInteger).value,
            greaterThan(0),
            reason: 'code $code would advance by 0');
      }
    });
  });
}
