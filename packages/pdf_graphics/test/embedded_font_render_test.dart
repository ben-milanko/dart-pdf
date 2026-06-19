import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

import 'generated_appearance_test.dart' show CountingDevice;

/// The font fixture lives in pdf_document's test tree; tests run from the
/// package directory, so reach across the workspace for it.
final _fontBytes =
    File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync();

void main() {
  PdfDocument freeTextWith(String text, PdfEmbeddedFont font) {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addFreeText(0, const PdfRect(72, 600, 320, 680), text, font: font);
    return PdfDocument.open(editor.save());
  }

  CountingDevice render(PdfDocument doc) {
    final device = CountingDevice();
    final page = doc.page(0);
    PdfInterpreter(cos: doc.cos, device: device)
      ..drawPage(page)
      ..drawAnnotations(page);
    return device;
  }

  test('an embedded-font free text extracts its text through ToUnicode', () {
    final device = render(freeTextWith(
        'Hello world', PdfEmbeddedFont.parse(_fontBytes)));
    final shown = device.texts.map((t) => t.text).join();
    expect(shown, contains('Hello world'));
  });

  test('non-Latin text the base-14 fonts cannot encode survives embedding',
      () {
    // 'é' and the Greek capital omega — outside the base-14 reach, the
    // whole point of embedding.
    final device =
        render(freeTextWith('café Ω', PdfEmbeddedFont.parse(_fontBytes)));
    final shown = device.texts.map((t) => t.text).join();
    expect(shown, contains('café'));
    expect(shown, contains('Ω'));
  });

  test('the run carries the embedded font name and real glyph outlines', () {
    // The interpreter resolves the embedded font program, so the run names
    // the embedded face and exposes vector outlines — devices paint these
    // rather than substituting a system font.
    final device =
        render(freeTextWith('Ag', PdfEmbeddedFont.parse(_fontBytes)));
    final run = device.texts.firstWhere((t) => t.text.contains('Ag'));
    expect(run.fontName, contains('DejaVu'));
    expect(run.hasOutlines, isTrue,
        reason: 'embedded glyphs should expose real outlines');
  });
}
