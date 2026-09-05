import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfLineEnding, PdfTextAlign;
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
      a.textAlign = PdfTextAlign.center;
      a.opacity = 0.5;
      a.fingerDrawsInk = false;
      a.showThumbnailSidebar = false; // non-default, so the write is real
      a.showAnnotationSidebar = true;
      a.showAnnotationLibraryPanel = true;
      a.annotationLibraryPanelWidth = 336;
      a.annotationLibraryPanelDock = PdfPanelDock.left;
      a.author = 'Ben';
      a.colorPickerFormat = PdfColorFormat.cmyk;
      a.highlightFormFields = false;
      a.showScrollbarChapters = true;
      a.showReflowView = true;
      a.lineStartEnding = PdfLineEnding.circle;
      a.lineEndEnding = PdfLineEnding.closedArrow;
      a.searchMatchCase = true;
      a.searchWholeWord = true;
      a.searchRegex = true;
      a.searchAnnotations = false; // non-default, so the write is real
      a.stampDateFormat = PdfStampDateFormat.dayMonthYear;
      a.stampTimeFormat = PdfStampTimeFormat.twelveHourSeconds;
      a.locale = const Locale('es');
      a.toolbarDock = PdfPanelDock.right;
      await pumpEventQueue(); // let the unawaited writes land

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.color, const Color(0xFF123456));
      expect(b.strokeWidth, 5);
      expect(b.fontSize, 18);
      expect(b.textAlign, PdfTextAlign.center);
      expect(b.opacity, 0.5);
      expect(b.fingerDrawsInk, isFalse);
      expect(b.showThumbnailSidebar, isFalse);
      expect(b.showAnnotationSidebar, isTrue);
      expect(b.showAnnotationLibraryPanel, isTrue);
      expect(b.annotationLibraryPanelWidth, 336);
      expect(b.annotationLibraryPanelDock, PdfPanelDock.left);
      expect(b.author, 'Ben');
      expect(b.colorPickerFormat, PdfColorFormat.cmyk);
      expect(b.highlightFormFields, isFalse);
      expect(b.showScrollbarChapters, isTrue);
      expect(b.showReflowView, isTrue);
      expect(b.lineStartEnding, PdfLineEnding.circle);
      expect(b.lineEndEnding, PdfLineEnding.closedArrow);
      expect(b.searchMatchCase, isTrue);
      expect(b.searchWholeWord, isTrue);
      expect(b.searchRegex, isTrue);
      expect(b.searchAnnotations, isFalse);
      expect(b.stampDateFormat, PdfStampDateFormat.dayMonthYear);
      expect(b.stampTimeFormat, PdfStampTimeFormat.twelveHourSeconds);
      expect(b.locale, const Locale('es'));
      expect(b.toolbarDock, PdfPanelDock.right);
    });

    test('locale persists as a BCP-47 tag and restores script/region subtags',
        () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      // A script+region-bearing tag exercises the tag parser both ways.
      a.locale = const Locale.fromSubtags(
          languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.locale?.languageCode, 'zh');
      expect(b.locale?.scriptCode, 'Hans');
      expect(b.locale?.countryCode, 'CN');

      // Clearing it back to "System default" removes the stored value.
      b.locale = null;
      await pumpEventQueue();
      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.locale, isNull);
    });

    test('noteRecentColor moves to front, dedupes, caps, and persists',
        () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      expect(a.recentColors, isEmpty);

      // alpha is dropped and RGB deduplicated; newest goes first
      a.noteRecentColor(const Color(0xFFE53935));
      a.noteRecentColor(const Color(0x8043A047));
      a.noteRecentColor(const Color(0xFFE53935)); // re-pick moves it to front
      expect(a.recentColors,
          const [Color(0xFF43A047), Color(0xFFE53935)].reversed.toList());
      expect(a.recentColors.first, const Color(0xFFE53935));
      expect(a.recentColors.length, 2);

      // re-noting the newest colour (any alpha) is a no-op: no duplicate,
      // no reorder, no listener churn
      var notified = 0;
      a.addListener(() => notified++);
      a.noteRecentColor(const Color(0x00E53935)); // same RGB, alpha ignored
      a.noteRecentColor(const Color(0xFFE53935));
      expect(notified, 0);

      // the cap holds: pushing 20 distinct colours keeps only the newest 18
      for (var i = 0; i < 20; i++) {
        a.noteRecentColor(Color(0xFF000000 | i));
      }
      expect(a.recentColors.length, 18);
      expect(a.recentColors.first, const Color(0xFF000013)); // 19th push (i=19)
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.recentColors, a.recentColors);
    });

    test('empty storage leaves the defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      expect(prefs.color, const Color(0xFFE53935));
      expect(prefs.strokeWidth, 2);
      expect(prefs.fontSize, 14);
      expect(prefs.textAlign, isNull); // null = follow text direction
      expect(prefs.opacity, 1);
      expect(prefs.fingerDrawsInk, isTrue);
      // the thumbnail strip is on by default since 9bbfc87
      expect(prefs.showThumbnailSidebar, isTrue);
      expect(prefs.showAnnotationSidebar, isFalse);
      expect(prefs.showAnnotationLibraryPanel, isFalse);
      expect(prefs.annotationLibraryPanelWidth, isNull);
      expect(prefs.annotationLibraryPanelDock, PdfPanelDock.right);
      expect(prefs.author, isNull);
      expect(prefs.colorPickerFormat, PdfColorFormat.hex);
      expect(prefs.lineStartEnding, PdfLineEnding.none);
      expect(prefs.lineEndEnding, PdfLineEnding.none);
      expect(prefs.highlightFormFields, isTrue);
      expect(prefs.showScrollbarChapters, isFalse);
      expect(prefs.showReflowView, isFalse);
      expect(prefs.searchMatchCase, isFalse);
      expect(prefs.searchWholeWord, isFalse);
      expect(prefs.searchRegex, isFalse);
      expect(prefs.searchAnnotations, isTrue); // on by default
      expect(prefs.stampDateFormat, PdfStampDateFormat.iso);
      expect(prefs.stampTimeFormat, PdfStampTimeFormat.twentyFourHour);
    });

    test('textAlign resets to null (follow text direction)', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      a.textAlign = PdfTextAlign.right;
      await pumpEventQueue();
      a.textAlign = null; // clear the override, back to follow-direction
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.textAlign, isNull);
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
      expect(editing.preferences.strokeWidth, 6);
      expect(editing.preferences.fontSize, 22);
      expect(editing.preferences.opacity, 0.4);
      expect(editing.preferences.fingerDrawsInk, isFalse);
    });

    test('controller setters write through to storage', () async {
      SharedPreferences.setMockInitialValues({});
      final first = PdfEditingController(buildMultiPagePdf(1));
      await first.preferences.ready;
      first
        ..color = const Color(0xFF0000FF)
        ..preferences.strokeWidth = 7
        ..preferences.opacity = 0.8;
      await pumpEventQueue();

      // a later session: new controller, its own preferences instance
      final second = PdfEditingController(buildMultiPagePdf(1));
      await second.preferences.ready;
      expect(second.color, const Color(0xFF0000FF));
      expect(second.preferences.strokeWidth, 7);
      expect(second.preferences.opacity, 0.8);
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

  group('per-tool style memory', () {
    test('each tool remembers its own style', () async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      await editing.preferences.ready;

      editing.tool = PdfEditTool.ink;
      editing.color = const Color(0xFFFF0000);
      editing.preferences.strokeWidth = 6;

      editing.tool = PdfEditTool.rectangle;
      editing.color = const Color(0xFF0000FF);
      editing.preferences.strokeWidth = 2;
      editing.preferences.shapeFillColor = const Color(0xFF00FF00);

      // arming the rectangle didn't disturb ink's remembered style
      editing.tool = PdfEditTool.ink;
      expect(editing.color, const Color(0xFFFF0000));
      expect(editing.preferences.strokeWidth, 6);

      editing.tool = PdfEditTool.rectangle;
      expect(editing.color, const Color(0xFF0000FF));
      expect(editing.preferences.strokeWidth, 2);
      expect(editing.preferences.shapeFillColor, const Color(0xFF00FF00));
    });

    test('the markup scope keeps the highlighter its own colour', () async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      await editing.preferences.ready;

      editing.useMarkupStyleScope();
      editing.color = const Color(0xFFFFEB3B); // yellow

      editing.tool = PdfEditTool.ink;
      editing.color = const Color(0xFF000000); // black ink

      editing.useMarkupStyleScope();
      expect(editing.color, const Color(0xFFFFEB3B));
    });

    test('color locking preserves tool colours behind the locked value',
        () async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      await editing.preferences.ready;

      editing
        ..tool = PdfEditTool.ink
        ..color = const Color(0xFF123456)
        ..colorLocked = true
        ..tool = PdfEditTool.highlight;

      expect(editing.color, const Color(0xFF123456));
      expect(editing.preferences.strokeWidth, 12);
      expect(editing.preferences.opacity, 0.45);

      editing.colorLocked = false;
      expect(editing.color, const Color(0xFFFFD100));
      editing.tool = PdfEditTool.ink;
      expect(editing.color, const Color(0xFF123456));
    });

    test('a tool with no saved style inherits the current value', () async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      await editing.preferences.ready;

      editing.color = const Color(0xFF112233); // no tool armed (shared)
      editing.tool = PdfEditTool.note; // never styled before
      expect(editing.color, const Color(0xFF112233));
    });

    test('per-tool styles survive into a fresh session', () async {
      SharedPreferences.setMockInitialValues({});
      final first = PdfEditingController(buildMultiPagePdf(1));
      await first.preferences.ready;
      first.tool = PdfEditTool.ink;
      first.color = const Color(0xFF8E24AA);
      first.tool = PdfEditTool.rectangle;
      first.color = const Color(0xFF00ACC1);
      await pumpEventQueue(); // let the unawaited writes land

      final second = PdfEditingController(buildMultiPagePdf(1));
      await second.preferences.ready;
      second.tool = PdfEditTool.ink;
      expect(second.color, const Color(0xFF8E24AA));
      second.tool = PdfEditTool.rectangle;
      expect(second.color, const Color(0xFF00ACC1));
    });
  });
}
