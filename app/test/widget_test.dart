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
    // use-deferred-loading makes the localizations delegate load
    // asynchronously; settle so the localized empty state builds.
    await tester.pumpAndSettle();

    // No document open yet: the empty state offers a way in.
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });

  testWidgets('a DevTools locale override forces the app onto that locale',
      (WidgetTester tester) async {
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

    // Arabic is not in supportedLocales, but the override wins over platform
    // resolution and flips Directionality to RTL - the seam the RTL layout
    // sweep is tested through. App strings still fall back to English.
    AppDevTools.instance.localeOverride.value = const Locale('ar');
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pumpAndSettle();

    final direction =
        Directionality.of(tester.element(find.byType(Scaffold).first));
    expect(direction, TextDirection.rtl);
    // The empty state's English fallback is unaffected by the missing ar ARB.
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);
  });
}
