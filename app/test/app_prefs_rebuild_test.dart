import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/app.dart';
import 'package:dart_pdf_editor_app/devtools.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

// A preference tick (every slider onChanged writes one) used to rebuild the
// whole window shell: MaterialApp, both ThemeData(colorSchemeSeed) and, via
// Navigator's route refresh, the entire EditorScreen. The shell now rebuilds
// only when something MaterialApp reads changes - these pin both halves.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() {
    AppDevTools.instance.localeOverride.value = null;
    AppDevTools.instance.showPerformanceOverlay.value = false;
    debugOnRebuildDirtyWidget = null;
  });

  PdfEditingPreferences prefsOf(WidgetTester tester) =>
      tester.widget<EditorScreen>(find.byType(EditorScreen)).prefs;

  testWidgets('a tool-style preference tick leaves the app shell alone',
      (tester) async {
    // The checked-in 40-page letterhead report at a desktop window size, so
    // the count below covers the real editor chrome, thumbnail strip and
    // viewer rather than an empty state.
    final bytes = File('../test_corpora/dartpdf/letterhead-report-40p.pdf')
        .readAsBytesSync();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      await tester.pumpWidget(const DartPdfEditorApp());
      await tester.pumpAndSettle();
      const codec = StandardMethodCodec();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        IncomingFileService.channelName,
        codec.encodeMethodCall(
            MethodCall('openFile', {'name': 'report.pdf', 'bytes': bytes})),
        (_) {},
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(PdfEditorView), findsOneWidget);

      final prefs = prefsOf(tester);
      var ticks = 0;
      void onTick() => ticks++;
      prefs.addListener(onTick);
      var total = 0, shell = 0, editorScreen = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        total++;
        if (element.widget is MaterialApp) shell++;
        if (element.widget is EditorScreen) editorScreen++;
      };
      for (var i = 1; i <= 10; i++) {
        // A stroke-width slider drag writes the preference on every tick.
        prefs.strokeWidth = 2.0 + i * 0.25;
        await tester.pump(const Duration(milliseconds: 16));
      }
      debugOnRebuildDirtyWidget = null;
      prefs.removeListener(onTick);
      expect(ticks, 10);

      expect(shell, 0, reason: 'MaterialApp rebuilt on a stroke-width tick');
      expect(editorScreen, 0,
          reason: 'EditorScreen rebuilt on a stroke-width tick');
      // Deterministic element-rebuild count for this document and window:
      // 1,368 per tick when the shell rebuilt MaterialApp + EditorScreen,
      // 1,034 without. What remains is PdfEditorView's own preference
      // listener (a separate follow-up), so this ceiling only guards the
      // shell half.
      expect(total ~/ ticks, lessThanOrEqualTo(1100),
          reason: 'element rebuilds per stroke-width tick');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a saved theme and language apply once preferences load',
      (tester) async {
    // The window builds before the asynchronous preference load lands; the
    // load's own notification is what switches the shell to the saved values.
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor.editing.themeMode': 'dark',
      'dart_pdf_editor.editing.locale': 'es',
    });
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pumpAndSettle();
    expect(prefsOf(tester).themePreference, PdfThemePreference.dark);
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('welcome-open-pdf'))))
          .brightness,
      Brightness.dark,
    );
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('welcome-open-pdf')),
            matching: find.text('Abrir un PDF')),
        findsOneWidget);
  });

  testWidgets('theme mode, language and the DevTools overrides switch live',
      (tester) async {
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pumpAndSettle();
    final prefs = prefsOf(tester);
    Brightness brightness() =>
        Theme.of(tester.element(find.byKey(const ValueKey('welcome-open-pdf'))))
            .brightness;
    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(brightness(), Brightness.light);
    prefs.themePreference = PdfThemePreference.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    prefs.themePreference = PdfThemePreference.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);

    // The Settings language picker.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('welcome-open-pdf')),
            matching: find.text('Open a PDF')),
        findsOneWidget);
    prefs.locale = const Locale('es');
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('welcome-open-pdf')),
            matching: find.text('Abrir un PDF')),
        findsOneWidget);
    prefs.locale = null;
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('welcome-open-pdf')),
            matching: find.text('Open a PDF')),
        findsOneWidget);

    // The DevTools locale override wins over the (unset) Settings choice.
    AppDevTools.instance.localeOverride.value = const Locale('es');
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('welcome-open-pdf')),
            matching: find.text('Abrir un PDF')),
        findsOneWidget);
    AppDevTools.instance.localeOverride.value = null;
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('welcome-open-pdf')),
            matching: find.text('Open a PDF')),
        findsOneWidget);

    expect(app().showPerformanceOverlay, isFalse);
    AppDevTools.instance.showPerformanceOverlay.value = true;
    await tester.pump();
    expect(app().showPerformanceOverlay, isTrue);
    AppDevTools.instance.showPerformanceOverlay.value = false;
    await tester.pump();
    expect(app().showPerformanceOverlay, isFalse);
  });
}
