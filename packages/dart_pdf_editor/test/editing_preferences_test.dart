import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart' show PdfLineEnding;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PdfEditingPreferences', () {
    test('changes persist and a fresh instance restores them', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      a.color = const Color(0xFF123456);
      a.strokeWidth = 5;
      a.fontSize = 18;
      a.opacity = 0.5;
      a.fingerDrawsInk = false;
      a.showThumbnailSidebar = false; // non-default, so the write is real
      a.showAnnotationSidebar = true;
      a.author = 'Ben';
      a.colorPickerFormat = PdfColorFormat.cmyk;
      a.highlightFormFields = false;
      a.showReflowView = true;
      a.lineStartEnding = PdfLineEnding.circle;
      a.lineEndEnding = PdfLineEnding.closedArrow;
      await pumpEventQueue(); // let the unawaited writes land

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.color, const Color(0xFF123456));
      expect(b.strokeWidth, 5);
      expect(b.fontSize, 18);
      expect(b.opacity, 0.5);
      expect(b.fingerDrawsInk, isFalse);
      expect(b.showThumbnailSidebar, isFalse);
      expect(b.showAnnotationSidebar, isTrue);
      expect(b.author, 'Ben');
      expect(b.colorPickerFormat, PdfColorFormat.cmyk);
      expect(b.highlightFormFields, isFalse);
      expect(b.showReflowView, isTrue);
      expect(b.lineStartEnding, PdfLineEnding.circle);
      expect(b.lineEndEnding, PdfLineEnding.closedArrow);
    });

    test('empty storage leaves the defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      expect(prefs.color, const Color(0xFFE53935));
      expect(prefs.strokeWidth, 2);
      expect(prefs.fontSize, 14);
      expect(prefs.opacity, 1);
      expect(prefs.fingerDrawsInk, isTrue);
      // the thumbnail strip is on by default since 9bbfc87
      expect(prefs.showThumbnailSidebar, isTrue);
      expect(prefs.showAnnotationSidebar, isFalse);
      expect(prefs.author, isNull);
      expect(prefs.colorPickerFormat, PdfColorFormat.hex);
      expect(prefs.lineStartEnding, PdfLineEnding.none);
      expect(prefs.lineEndEnding, PdfLineEnding.none);
      expect(prefs.highlightFormFields, isTrue);
      expect(prefs.showReflowView, isFalse);
    });

    test('a value set while loading is not clobbered by stored data', () async {
      SharedPreferences.setMockInitialValues(
          {'dart_pdf_editor.editing.strokeWidth': 9.0});
      final prefs = PdfEditingPreferences()..strokeWidth = 3;
      await prefs.ready;
      expect(prefs.strokeWidth, 3);
    });

    test('a new controller adopts the stored preferences', () async {
      SharedPreferences.setMockInitialValues({
        'dart_pdf_editor.editing.color': 0xFF00A040,
        'dart_pdf_editor.editing.strokeWidth': 6.0,
        'dart_pdf_editor.editing.fontSize': 22.0,
        'dart_pdf_editor.editing.opacity': 0.4,
        'dart_pdf_editor.editing.fingerDrawsInk': false,
      });
      final editing = PdfEditingController(buildMultiPagePdf(1));
      await editing.preferences.ready;
      expect(editing.color, const Color(0xFF00A040));
      expect(editing.strokeWidth, 6);
      expect(editing.fontSize, 22);
      expect(editing.opacity, 0.4);
      expect(editing.fingerDrawsInk, isFalse);
    });

    test('controller setters write through to storage', () async {
      SharedPreferences.setMockInitialValues({});
      final first = PdfEditingController(buildMultiPagePdf(1));
      await first.preferences.ready;
      first
        ..color = const Color(0xFF0000FF)
        ..strokeWidth = 7
        ..opacity = 0.8;
      await pumpEventQueue();

      // a later session: new controller, its own preferences instance
      final second = PdfEditingController(buildMultiPagePdf(1));
      await second.preferences.ready;
      expect(second.color, const Color(0xFF0000FF));
      expect(second.strokeWidth, 7);
      expect(second.opacity, 0.8);
    });

    test('preference changes notify controller listeners', () async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      await editing.preferences.ready;
      var notified = 0;
      editing.addListener(() => notified++);
      editing.preferences.color = const Color(0xFF112233);
      expect(notified, 1);
      expect(editing.color, const Color(0xFF112233));
    });
  });
}
