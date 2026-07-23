import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/app.dart';
import 'package:dart_pdf_editor_app/devtools.dart';

void main() {
  setUp(() {
    // The mock store is process-global; reset it so a prior test's persisted
    // preferences never leak into this one.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => AppDevTools.instance.localeOverride.value = null);

  testWidgets('boots into the empty state with an Open button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pumpAndSettle();

    // No document open yet: the empty state offers a way in.
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });

  testWidgets('switching locale at runtime immediately re-renders the UI',
      (WidgetTester tester) async {
    // Regression guard: with deferred locale loading the switch only landed
    // after the es library loaded asynchronously, so a language pick looked
    // like it did nothing (deferred loading is off - see doc/i18n.md). The app
    // boots English, then an override to es must flip the shipped Spanish
    // strings in without any extra async settling. The Settings language
    // picker drives the same MaterialApp.locale resolution as this override.
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);

    AppDevTools.instance.localeOverride.value = const Locale('es');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Abrir un PDF'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsNothing);
  });

  testWidgets('a DevTools override onto an unshipped RTL locale flips RTL '
      'while app strings fall back to English', (WidgetTester tester) async {
    // Forcing a locale with no shipped ARB makes Flutter log a debug-only
    // "not supported by all of its localization delegates" warning (app
    // strings fall back to English by design). That's expected for this
    // dev-only testing toggle; swallow just that warning so the test asserts
    // on the behaviour, not the diagnostic.
    final priorOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details
          .exceptionAsString()
          .contains('not supported by all of its localization delegates')) {
        return;
      }
      priorOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = priorOnError);

    // Hebrew is not in supportedLocales (Arabic now is - see the next test),
    // but the override wins over platform resolution and flips Directionality
    // to RTL - the seam the RTL layout sweep is tested through. App strings
    // still fall back to English because no he ARB ships.
    AppDevTools.instance.localeOverride.value = const Locale('he');
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pumpAndSettle();

    final direction =
        Directionality.of(tester.element(find.byType(Scaffold).first));
    expect(direction, TextDirection.rtl);
    // The empty state's English fallback is unaffected by the missing he ARB.
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);
  });

  testWidgets('the shipped Arabic locale renders RTL with translated strings',
      (WidgetTester tester) async {
    // Arabic is a shipped locale now, so forcing it must both flip
    // Directionality to RTL and swap in the Arabic ARB - the end-to-end proof
    // that supportedLocales, the generated delegate, and the app's ar ARB are
    // all wired for the first RTL locale we ship.
    AppDevTools.instance.localeOverride.value = const Locale('ar');
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pumpAndSettle();

    final direction =
        Directionality.of(tester.element(find.byType(Scaffold).first));
    expect(direction, TextDirection.rtl);
    expect(find.widgetWithText(FilledButton, 'فتح ملف PDF'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsNothing);
  });
}
