import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/app.dart';
import 'package:dart_pdf_editor_app/devtools.dart';

// The end-to-end check that Spanish - the first real shipped locale - is wired
// all the way through: supportedLocales includes es, the generated es delegate
// loads, and the app ARB's Spanish strings reach the painted UI.
//
// This lives in its own file on purpose. The es localization is a deferred
// (async-loaded) library; once another localized app has booted in the same
// test isolate, the es delegate's load races the test pump and never settles
// (see doc/i18n.md's deferred-loading note). A single-test file keeps this boot
// first in its isolate, so the load completes deterministically. The Settings
// language preference feeds the same MaterialApp.locale resolution as this
// override; its persistence is unit-tested in dart_pdf_editor's
// editing_preferences_test.dart, and the picker UI in app's settings_menu_test.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppDevTools.instance.localeOverride.value = null);

  testWidgets('renders the shipped Spanish ARB when resolved to es',
      (WidgetTester tester) async {
    AppDevTools.instance.localeOverride.value = const Locale('es');
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pumpAndSettle();

    // The empty-state button is Spanish; the English label is gone.
    expect(find.widgetWithText(FilledButton, 'Abrir un PDF'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsNothing);
  });
}
