// Non-English locales under a material_ui MaterialApp. The generated
// DartPdfEditorLocalizations.localizationsDelegates still lists the legacy
// flutter_localizations delegates, so an app that registers it gets no
// material_ui MaterialLocalizations for, say, Ukrainian (material_ui's own
// defaults are English-only): before the wrapper filled them in, the editor
// crashed there. PdfEditorLocalizations.delegates is the list to register.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_host.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {required Locale locale,
    required List<LocalizationsDelegate<dynamic>> delegates}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: delegates,
    supportedLocales: DartPdfEditorLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

/// Opens a stock dialog from the editor (running [check] on its context),
/// its text field's context menu, and a notice with Undo.
Future<void> _exercise(WidgetTester tester,
    {void Function(BuildContext dialog)? check}) async {
  final context = pdfEditorContext(tester);
  showPdfTextPrompt(context, title: 'Name', initial: 'hello');
  await tester.pumpAndSettle();
  final field = find.byKey(const ValueKey('pdf-text-prompt-field'));
  expect(field, findsOneWidget);
  await tester.tap(field,
      kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('pdf-text-context-menu')), findsOneWidget);
  check?.call(tester.element(field));
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  PdfEditorPresenter.of(context)
      .notice(context, PdfEditorNotice('x', onUndo: () {}));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'uk with the generated (legacy) delegate list: the editor builds and '
      'its dialogs, menus and notices work', (tester) async {
    await _pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)),
        locale: const Locale('uk'),
        delegates: DartPdfEditorLocalizations.localizationsDelegates);
    // the host's own misconfiguration, reported once by its Localizations
    // (material_ui's app defaults are English-only) - not an editor error
    expect('${tester.takeException()}', contains('is not supported'));
    expectNoHostErrors(tester);
    await _exercise(tester, check: (dialog) {
      // the wrapper supplied material_ui's Ukrainian strings
      expect(MaterialLocalizations.of(dialog).cancelButtonLabel,
          isNot(const DefaultMaterialLocalizations().cancelButtonLabel));
      expect(pdfL10n(dialog).localeName, 'uk');
    });
    expectNoHostErrors(tester);
  });

  testWidgets('de with PdfEditorLocalizations.delegates', (tester) async {
    await _pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)),
        locale: const Locale('de'),
        delegates: PdfEditorLocalizations.delegates);
    expectNoHostErrors(tester);
    // a host that registers the list needs no wrapper at all
    final hostElement = tester.element(find.byType(PdfMaterialHost).first);
    Element? child;
    hostElement.visitChildren((c) => child = c);
    expect(child!.widget, isA<Builder>());

    await _exercise(tester, check: (dialog) {
      expect(MaterialLocalizations.of(dialog).cancelButtonLabel, 'Abbrechen');
    });
    expect(find.text('Rückgängig'), findsOneWidget); // the notice's Undo
    expectNoHostErrors(tester);
  });

  testWidgets('ar (right-to-left) with PdfEditorLocalizations.delegates',
      (tester) async {
    await _pump(tester, PdfReader(bytes: buildMultiPagePdf(2)),
        locale: const Locale('ar'),
        delegates: PdfEditorLocalizations.delegates);
    expect(Directionality.of(pdfEditorContext(tester)), TextDirection.rtl);
    await _exercise(tester);
    expectNoHostErrors(tester);
  });
}
